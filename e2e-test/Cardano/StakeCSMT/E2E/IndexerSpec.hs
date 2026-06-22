module Cardano.StakeCSMT.E2E.IndexerSpec
    ( spec
    ) where

import Cardano.Crypto.Hash.Class
    ( hashFromBytes
    )
import Cardano.Ledger.Coin
    ( Coin (..)
    )
import Cardano.Ledger.Credential
    ( Credential (KeyHashObj)
    )
import Cardano.Ledger.Keys
    ( KeyHash (..)
    , KeyRole (Staking)
    )
import Cardano.Node.Client.E2E.Devnet
    ( withCardanoNode
    )
import Cardano.Node.Client.N2C.ChainSync
    ( Fetched (..)
    , HeaderPoint
    )
import Cardano.StakeCSMT.CSMT.Builder
    ( buildCredentialProof
    , queryEpochRoot
    , verifyCredentialProof
    )
import Cardano.StakeCSMT.CSMT.Codecs
    ( EpochRoot
    , Hash
    )
import Cardano.StakeCSMT.CSMT.Columns qualified as Stake
import Cardano.StakeCSMT.CSMT.RocksDB
    ( mkStakeCSMTDatabase
    , withStakeCSMTRocksDB
    )
import Cardano.StakeCSMT.History.Builder
    ( buildEpochRootProof
    , queryHistoryLeaf
    , queryHistoryRoot
    , verifyEpochRootProof
    )
import Cardano.StakeCSMT.History.Columns qualified as History
import Cardano.StakeCSMT.History.RocksDB
    ( mkHistoryDatabase
    , withHistoryRocksDB
    )
import Cardano.StakeCSMT.Indexer
    ( IndexedEpoch (..)
    , runIndexerWith
    )
import Cardano.StakeCSMT.Ledger.Checkpoint
    ( ReplayCheckpoint (replayCheckpointPoint)
    )
import Cardano.StakeCSMT.Ledger.Config
    ( LedgerConfigBundle
    , ledgerConfigPathsFromDirectory
    , loadLedgerConfig
    )
import Cardano.StakeCSMT.Ledger.Replay
    ( EpochTransition
    , ReplayChainSyncRunner
    , ReplayCheckpointConfig (..)
    , ReplayFollowerConfig (..)
    , defaultReplayChainSyncRunner
    , replayBlock
    , runReplayFollowerWith
    )
import ChainFollower
    ( Follower (..)
    , Intersector (..)
    , ProgressOrRewind (..)
    )
import Control.Exception
    ( Exception
    , SomeException
    , fromException
    , throwIO
    , try
    )
import Control.Monad
    ( foldM
    , when
    )
import Data.ByteString qualified as BS
import Data.IORef
    ( modifyIORef'
    , newIORef
    , readIORef
    , writeIORef
    )
import Data.Map.Strict qualified as Map
import Database.KV.Database
    ( Database
    )
import Database.KV.Transaction
    ( runTransactionUnguarded
    )
import Ouroboros.Consensus.Block
    ( blockPoint
    , blockSlot
    , getHeader
    )
import Ouroboros.Network.Block qualified as Network
import Ouroboros.Network.Magic
    ( NetworkMagic (..)
    )
import Ouroboros.Network.Point qualified as Network.Point
import System.FilePath
    ( takeDirectory
    )
import System.IO.Temp
    ( withSystemTempDirectory
    )
import System.Timeout
    ( timeout
    )
import Test.Hspec
    ( Spec
    , describe
    , expectationFailure
    , it
    , shouldBe
    , shouldSatisfy
    )

genesisDir :: FilePath
genesisDir = "e2e-test/genesis"

data CaptureComplete = CaptureComplete
    deriving stock (Show)

instance Exception CaptureComplete

data CapturedReplay = CapturedReplay
    { capturedFetchedBlocks :: ![Fetched]
    , capturedBoundaryIndex :: !Int
    }

data IndexerObservation = IndexerObservation
    { observedIndexedEpoch :: !IndexedEpoch
    , observedEpochRoot :: !EpochRoot
    , observedHistoryRoot :: !Hash
    , observedHistoryLeaf :: !EpochRoot
    , observedCredentialCoin :: !Coin
    }
    deriving stock (Eq, Show)

spec :: Spec
spec =
    describe "Indexer devnet replay"
        $ it "indexes deterministic epoch roots across checkpoint recovery"
        $ withCardanoNode genesisDir
        $ \socketPath _startMs -> do
            let nodeRuntimeDir = takeDirectory socketPath
                config =
                    ReplayFollowerConfig
                        { replayFollowerSocketPath = socketPath
                        , replayFollowerNetworkMagic = NetworkMagic 42
                        , replayFollowerByronEpochSlots = 21_600
                        }
            bundle <-
                loadLedgerConfig
                    $ ledgerConfigPathsFromDirectory nodeRuntimeDir
            CapturedReplay{..} <-
                captureDevnetFetchedThroughTransition bundle config
            length capturedFetchedBlocks `shouldSatisfy` (> 0)

            directObservation <-
                runCapturedIndexer
                    bundle
                    config
                    capturedFetchedBlocks
                    (capturedRunner capturedFetchedBlocks)
                    False
            recoveredObservation <-
                runCapturedIndexer
                    bundle
                    config
                    capturedFetchedBlocks
                    ( rollbackCapturedRunner
                        capturedFetchedBlocks
                        capturedBoundaryIndex
                    )
                    True

            recoveredObservation `shouldBe` directObservation

captureDevnetFetchedThroughTransition
    :: LedgerConfigBundle
    -> ReplayFollowerConfig
    -> IO CapturedReplay
captureDevnetFetchedThroughTransition bundle config = do
    fetchedRef <- newIORef []
    boundaryIndexRef <- newIORef Nothing
    let recordEpochTransition :: EpochTransition -> IO ()
        recordEpochTransition _transition = do
            fetchedCount <- length <$> readIORef fetchedRef
            writeIORef boundaryIndexRef $ Just $ fetchedCount - 1
            throwIO CaptureComplete
        replayAction state block = do
            let fetched =
                    Fetched
                        { fetchedPoint = blockPoint $ getHeader block
                        , fetchedBlock = block
                        , fetchedTip = blockSlot block
                        }
            modifyIORef' fetchedRef (<> [fetched])
            replayBlock bundle recordEpochTransition state block

    result <-
        timeout 75_000_000
            $ try
            $ runReplayFollowerWith
                defaultReplayChainSyncRunner
                replayAction
                bundle
                config
    case result of
        Nothing ->
            expectationFailure
                "timed out before observing a devnet epoch transition"
        Just runnerResult ->
            handleCaptureResult runnerResult
    fetchedBlocks <- readIORef fetchedRef
    boundaryIndex <-
        expectJust
            "expected a captured epoch transition index"
            =<< readIORef boundaryIndexRef
    length fetchedBlocks `shouldSatisfy` (> boundaryIndex)
    boundaryIndex `shouldSatisfy` (> 0)
    pure
        CapturedReplay
            { capturedFetchedBlocks = fetchedBlocks
            , capturedBoundaryIndex = boundaryIndex
            }

handleCaptureResult
    :: Either SomeException (Either SomeException ())
    -> IO ()
handleCaptureResult =
    \case
        Left err ->
            handleCaptureException err
        Right (Left err) ->
            handleCaptureException err
        Right (Right ()) ->
            expectationFailure
                "expected devnet capture to stop at an epoch transition"

handleCaptureException :: SomeException -> IO ()
handleCaptureException err =
    case fromException err of
        Just CaptureComplete ->
            pure ()
        Nothing ->
            expectationFailure
                $ "expected devnet capture not to fail, got "
                    <> show err

runCapturedIndexer
    :: LedgerConfigBundle
    -> ReplayFollowerConfig
    -> [Fetched]
    -> ReplayChainSyncRunner
    -> Bool
    -> IO IndexerObservation
runCapturedIndexer bundle config fetchedBlocks runner expectCheckpointLoad =
    withSystemTempDirectory "stake-csmt-e2e-indexer-stake"
        $ \stakeDirectory ->
            withSystemTempDirectory "stake-csmt-e2e-indexer-history"
                $ \historyDirectory ->
                    withSystemTempDirectory
                        "stake-csmt-e2e-indexer-checkpoints"
                        $ \checkpointDirectory ->
                            withStakeCSMTRocksDB stakeDirectory
                                $ \stakeRocksDB ->
                                    withHistoryRocksDB historyDirectory
                                        $ \historyRocksDB -> do
                                            let stakeDb =
                                                    mkStakeCSMTDatabase
                                                        stakeRocksDB
                                                historyDb =
                                                    mkHistoryDatabase
                                                        historyRocksDB
                                            savedStates <- newIORef Map.empty
                                            loadedRef <- newIORef False
                                            indexedRef <- newIORef []
                                            let checkpointConfig =
                                                    ReplayCheckpointConfig
                                                        { replayCheckpointDirectory =
                                                            checkpointDirectory
                                                        , replayCheckpointTailLimit =
                                                            length
                                                                fetchedBlocks
                                                                + 2
                                                        , replayCheckpointCadence =
                                                            1
                                                        , replayCheckpointSaveState =
                                                            \checkpoint state ->
                                                                modifyIORef'
                                                                    savedStates
                                                                    $ Map.insert
                                                                        ( replayCheckpointPoint
                                                                            checkpoint
                                                                        )
                                                                        state
                                                        , replayCheckpointLoadState =
                                                            \checkpoint -> do
                                                                writeIORef
                                                                    loadedRef
                                                                    True
                                                                Map.lookup
                                                                    ( replayCheckpointPoint
                                                                        checkpoint
                                                                    )
                                                                    <$> readIORef
                                                                        savedStates
                                                        }
                                                hook _transition =
                                                    maybe (pure ()) $ \indexed ->
                                                        modifyIORef'
                                                            indexedRef
                                                            (<> [indexed])
                                            result <-
                                                runIndexerWith
                                                    runner
                                                    bundle
                                                    stakeDb
                                                    historyDb
                                                    config
                                                    checkpointConfig
                                                    (Just hook)
                                            case result of
                                                Left err ->
                                                    expectationFailure
                                                        $ "expected indexer replay to finish, got "
                                                            <> show err
                                                Right () ->
                                                    pure ()
                                            when expectCheckpointLoad $ do
                                                loaded <- readIORef loadedRef
                                                loaded `shouldBe` True
                                            indexedEpoch <-
                                                expectLastIndexed
                                                    =<< readIORef
                                                        indexedRef
                                            queryIndexerObservation
                                                stakeDb
                                                historyDb
                                                indexedEpoch

queryIndexerObservation
    :: Database IO stakeCf Stake.Columns stakeOps
    -> Database IO historyCf History.Columns historyOps
    -> IndexedEpoch
    -> IO IndexerObservation
queryIndexerObservation stakeDb historyDb indexed = do
    let epoch = indexedEpoch indexed
    epochRoot <-
        expectJust "expected stored indexed epoch root"
            =<< runTransactionUnguarded stakeDb (queryEpochRoot epoch)
    epochRoot `shouldBe` indexedEpochRoot indexed
    (credentialCoin, credentialProof) <-
        expectJust "expected devnet genesis credential proof"
            =<< runTransactionUnguarded
                stakeDb
                (buildCredentialProof epoch e2eGenesisStakingCredential)
    credentialCoin `shouldBe` e2eGenesisStake
    verifyCredentialProof
        epochRoot
        e2eGenesisStakingCredential
        credentialCoin
        credentialProof
        `shouldBe` True
    historyRoot <-
        expectJust "expected indexed history root"
            =<< runTransactionUnguarded historyDb queryHistoryRoot
    historyRoot `shouldBe` indexedHistoryRoot indexed
    historyLeaf <-
        expectJust "expected indexed history leaf"
            =<< runTransactionUnguarded historyDb (queryHistoryLeaf epoch)
    historyLeaf `shouldBe` epochRoot
    (proofEpochRoot, epochRootProof) <-
        expectJust "expected indexed epoch-root history proof"
            =<< runTransactionUnguarded
                historyDb
                (buildEpochRootProof epoch)
    proofEpochRoot `shouldBe` epochRoot
    verifyEpochRootProof
        historyRoot
        epoch
        epochRoot
        epochRootProof
        `shouldBe` True
    pure
        IndexerObservation
            { observedIndexedEpoch = indexed
            , observedEpochRoot = epochRoot
            , observedHistoryRoot = historyRoot
            , observedHistoryLeaf = historyLeaf
            , observedCredentialCoin = credentialCoin
            }

capturedRunner :: [Fetched] -> ReplayChainSyncRunner
capturedRunner fetchedBlocks _ _ _ _ _ Intersector{intersectFound} points = do
    assertOriginStart points
    follower0 <- intersectFound $ Network.Point Network.Point.Origin
    _follower <- foldM rollForwardFetched follower0 fetchedBlocks
    pure $ Right ()

rollbackCapturedRunner
    :: [Fetched]
    -> Int
    -> ReplayChainSyncRunner
rollbackCapturedRunner fetchedBlocks boundaryIndex _ _ _ _ _ intersector points = do
    assertOriginStart points
    follower0 <-
        intersectFound intersector $ Network.Point Network.Point.Origin
    followerAfterFirstPass <-
        foldM rollForwardFetched follower0 fetchedBlocks
    rollbackPoint <-
        retainedPointBeforeBoundary fetchedBlocks boundaryIndex
    recoveredFollower <-
        expectProgress "rollback before indexed boundary"
            =<< rollBackward followerAfterFirstPass rollbackPoint
    _followerAfterRecovery <-
        foldM
            rollForwardFetched
            recoveredFollower
            (drop boundaryIndex fetchedBlocks)
    pure $ Right ()

rollForwardFetched
    :: Follower HeaderPoint Network.SlotNo Fetched
    -> Fetched
    -> IO (Follower HeaderPoint Network.SlotNo Fetched)
rollForwardFetched follower fetched =
    rollForward follower fetched $ fetchedTip fetched

retainedPointBeforeBoundary :: [Fetched] -> Int -> IO HeaderPoint
retainedPointBeforeBoundary fetchedBlocks boundaryIndex =
    case splitAt boundaryIndex fetchedBlocks of
        (beforeBoundary, _boundary : _) ->
            pure $ fetchedPoint $ last beforeBoundary
        _ ->
            fail "expected a retained point before the indexed boundary"

assertOriginStart :: [Network.Point block] -> IO ()
assertOriginStart points =
    case points of
        [Network.Point Network.Point.Origin] ->
            pure ()
        other ->
            expectationFailure
                $ "expected [Origin], got "
                    <> show (length other)

expectProgress
    :: String
    -> ProgressOrRewind point tip block
    -> IO (Follower point tip block)
expectProgress context =
    \case
        Progress follower ->
            pure follower
        Rewind _ _ ->
            fail $ "expected progress for " <> context <> ", got rewind"
        Reset _ ->
            fail $ "expected progress for " <> context <> ", got reset"

expectLastIndexed :: [IndexedEpoch] -> IO IndexedEpoch
expectLastIndexed indexed =
    case reverse indexed of
        indexedEpoch : _ ->
            pure indexedEpoch
        [] ->
            fail "expected the indexer hook to report an indexed epoch"

expectJust :: String -> Maybe a -> IO a
expectJust _ (Just value) =
    pure value
expectJust context Nothing =
    fail context

e2eGenesisStakingCredential :: Credential Staking
e2eGenesisStakingCredential =
    case hashFromBytes e2eGenesisStakingCredentialBytes of
        Nothing -> error "invalid e2e genesis staking key hash bytes"
        Just keyHash -> KeyHashObj $ KeyHash keyHash

e2eGenesisStake :: Coin
e2eGenesisStake = Coin 30_000_000_000_000_000

e2eGenesisStakingCredentialBytes :: BS.ByteString
e2eGenesisStakingCredentialBytes =
    BS.pack
        [ 0x74
        , 0x1f
        , 0x46
        , 0x46
        , 0x5d
        , 0xa7
        , 0xe1
        , 0x7b
        , 0xe7
        , 0x94
        , 0xfd
        , 0xd6
        , 0x37
        , 0xa2
        , 0x7c
        , 0x0f
        , 0xc3
        , 0x81
        , 0x6f
        , 0x74
        , 0x81
        , 0x1d
        , 0x06
        , 0x01
        , 0x54
        , 0x3e
        , 0xdc
        , 0xfa
        ]
