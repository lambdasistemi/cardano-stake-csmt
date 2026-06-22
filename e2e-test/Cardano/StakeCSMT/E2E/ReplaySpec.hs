module Cardano.StakeCSMT.E2E.ReplaySpec
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
import Cardano.Slotting.Slot
    ( EpochNo (..)
    )
import Cardano.StakeCSMT.CSMT.Builder
    ( CredentialProof
    , buildCredentialProof
    , buildEpochCSMT
    , queryEpochRoot
    , verifyCredentialProof
    )
import Cardano.StakeCSMT.CSMT.Codecs
    ( EpochRoot
    , Hash
    )
import Cardano.StakeCSMT.CSMT.RocksDB
    ( mkStakeCSMTDatabase
    , withStakeCSMTRocksDB
    )
import Cardano.StakeCSMT.History.Builder
    ( EpochRootProof
    , buildEpochRootProof
    , finalizeEpochRoot
    , queryHistoryLeaf
    , queryHistoryRoot
    , verifyEpochRootProof
    )
import Cardano.StakeCSMT.History.RocksDB
    ( mkHistoryDatabase
    , withHistoryRocksDB
    )
import Cardano.StakeCSMT.Ledger.Checkpoint
    ( ReplayCheckpoint (..)
    , checkpointPointFromHeaderPoint
    , saveReplayCheckpoint
    )
import Cardano.StakeCSMT.Ledger.Config
    ( LedgerConfigBundle
    , ledgerConfigPathsFromDirectory
    , loadLedgerConfig
    )
import Cardano.StakeCSMT.Ledger.Replay
    ( ReplayChainSyncRunner
    , ReplayCheckpointConfig (..)
    , ReplayFollowerConfig (..)
    , ReplayState (..)
    , defaultReplayChainSyncRunner
    , initialReplayState
    , replayBlock
    , runReplayFollowerWith
    , runReplayFollowerWithCheckpoints
    )
import Cardano.StakeCSMT.Ledger.StakeSnapshot
    ( StakeSnapshot (..)
    )
import ChainFollower
    ( Follower (..)
    , Intersector (..)
    , ProgressOrRewind (..)
    )
import Control.Monad
    ( foldM
    )
import Data.ByteString qualified as BS
import Data.IORef
    ( modifyIORef'
    , newIORef
    , readIORef
    , writeIORef
    )
import Data.List
    ( nub
    )
import Data.Map.Strict qualified as Map
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

data FinalizedHistoryObservation = FinalizedHistoryObservation
    { finalizedEpochRoot :: EpochRoot
    , finalizedCredentialCoin :: Coin
    , finalizedCredentialProof :: CredentialProof
    , finalizedHistoryRoot :: Hash
    , finalizedHistoryLeaf :: EpochRoot
    , finalizedHistoryProof :: EpochRootProof
    }
    deriving (Show, Eq)

spec :: Spec
spec =
    describe "Replay devnet proof" $ do
        it "replays devnet chain sync blocks to tip without error"
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
                blockCountRef <- newIORef (0 :: Int)
                transitionsRef <- newIORef []
                let recordEpochTransition transition =
                        modifyIORef' transitionsRef (transition :)
                    replayAction state block = do
                        nextState <-
                            replayBlock
                                bundle
                                recordEpochTransition
                                state
                                block
                        modifyIORef' blockCountRef (+ 1)
                        pure nextState

                result <-
                    timeout 15_000_000
                        $ runReplayFollowerWith
                            defaultReplayChainSyncRunner
                            replayAction
                            bundle
                            config

                case result of
                    Just (Left err) ->
                        expectationFailure
                            $ "expected replay follower not to fail, got "
                                <> show err
                    _ ->
                        pure ()
                blockCount <- readIORef blockCountRef
                blockCount `shouldSatisfy` (> 0)
                transitions <- readIORef transitionsRef
                transitions `shouldBe` nub transitions

        it "recovers replay from a devnet checkpoint and retained tail"
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
                withFinalizedHistoryObservation
                    $ \beforeRollbackHistory queryFinalizedHistory -> do
                        fetchedBlocks <- captureDevnetFetchedBlocks bundle config 5
                        let boundaryFetched = fetchedBlocks !! 1
                            rollbackFetched = fetchedBlocks !! 2
                            scenarioBlocks = take 5 fetchedBlocks
                            boundaryBlocks = take 2 fetchedBlocks
                            boundaryPoint =
                                checkpointPointFromHeaderPoint
                                    $ fetchedPoint boundaryFetched
                        directState <- replayFetchedBlocks bundle scenarioBlocks
                        boundaryState <- replayFetchedBlocks bundle boundaryBlocks

                        withSystemTempDirectory
                            "stake-csmt-e2e-replay-checkpoints"
                            $ \checkpointDirectory -> do
                                let checkpoint =
                                        ReplayCheckpoint
                                            { replayCheckpointPoint =
                                                boundaryPoint
                                            , replayCheckpointFinalizedEpoch =
                                                replayStateLastEpoch
                                                    boundaryState
                                            , replayCheckpointObservedEpoch =
                                                replayStateLastEpoch
                                                    boundaryState
                                            }
                                _ <-
                                    saveReplayCheckpoint
                                        checkpointDirectory
                                        checkpoint
                                savedStates <-
                                    newIORef
                                        $ Map.singleton
                                            boundaryPoint
                                            boundaryState
                                recoveredRef <- newIORef Nothing
                                let checkpointConfig =
                                        ReplayCheckpointConfig
                                            { replayCheckpointDirectory =
                                                checkpointDirectory
                                            , replayCheckpointTailLimit = 8
                                            , replayCheckpointCadence = 0
                                            , replayCheckpointSaveState =
                                                \savedCheckpoint state ->
                                                    modifyIORef' savedStates
                                                        $ Map.insert
                                                            ( replayCheckpointPoint
                                                                savedCheckpoint
                                                            )
                                                            state
                                            , replayCheckpointLoadState =
                                                \savedCheckpoint ->
                                                    Map.lookup
                                                        ( replayCheckpointPoint
                                                            savedCheckpoint
                                                        )
                                                        <$> readIORef
                                                            savedStates
                                            }
                                    replayAction state block = do
                                        nextState <-
                                            replayBlock
                                                bundle
                                                (const $ pure ())
                                                state
                                                block
                                        writeIORef recoveredRef $ Just nextState
                                        pure nextState
                                    controlledRunner =
                                        rollbackRunner
                                            scenarioBlocks
                                            (fetchedPoint rollbackFetched)

                                result <-
                                    runReplayFollowerWithCheckpoints
                                        controlledRunner
                                        replayAction
                                        bundle
                                        config
                                        checkpointConfig

                                case result of
                                    Left err ->
                                        expectationFailure
                                            $ "expected rollback replay to finish, got "
                                                <> show err
                                    Right () ->
                                        pure ()
                                recovered <- readIORef recoveredRef
                                case recovered of
                                    Nothing ->
                                        expectationFailure
                                            "expected checkpoint replay to apply blocks"
                                    Just recoveredState -> do
                                        replayStateLastEpoch recoveredState
                                            `shouldBe` replayStateLastEpoch
                                                directState
                                        replayStateLedgerState recoveredState
                                            `shouldBe` replayStateLedgerState
                                                directState

                        afterRecoveryHistory <- queryFinalizedHistory
                        afterRecoveryHistory `shouldBe` beforeRollbackHistory
                        verifyFinalizedHistoryObservation afterRecoveryHistory
                            `shouldBe` True

captureDevnetFetchedBlocks
    :: LedgerConfigBundle
    -> ReplayFollowerConfig
    -> Int
    -> IO [Fetched]
captureDevnetFetchedBlocks bundle config expectedCount = do
    fetchedRef <- newIORef []
    let replayAction state block = do
            let fetched =
                    Fetched
                        { fetchedPoint = blockPoint $ getHeader block
                        , fetchedBlock = block
                        , fetchedTip = blockSlot block
                        }
            modifyIORef' fetchedRef $ \fetchedBlocks ->
                if length fetchedBlocks < expectedCount
                    then fetchedBlocks <> [fetched]
                    else fetchedBlocks
            replayBlock bundle (const $ pure ()) state block

    result <-
        timeout 8_000_000
            $ runReplayFollowerWith
                defaultReplayChainSyncRunner
                replayAction
                bundle
                config
    case result of
        Just (Left err) ->
            expectationFailure
                $ "expected devnet capture not to fail, got "
                    <> show err
        _ ->
            pure ()
    fetchedBlocks <- readIORef fetchedRef
    length fetchedBlocks `shouldSatisfy` (>= expectedCount)
    pure $ take expectedCount fetchedBlocks

replayFetchedBlocks
    :: LedgerConfigBundle
    -> [Fetched]
    -> IO ReplayState
replayFetchedBlocks bundle fetchedBlocks = do
    state0 <- initialReplayState bundle
    foldM
        ( \state fetched ->
            replayBlock bundle (const $ pure ()) state $ fetchedBlock fetched
        )
        state0
        fetchedBlocks

withFinalizedHistoryObservation
    :: (FinalizedHistoryObservation -> IO FinalizedHistoryObservation -> IO a)
    -> IO a
withFinalizedHistoryObservation action =
    withSystemTempDirectory "stake-csmt-e2e-finalized-csmt"
        $ \csmtDirectory ->
            withSystemTempDirectory "stake-csmt-e2e-finalized-history"
                $ \historyDirectory ->
                    withStakeCSMTRocksDB csmtDirectory $ \csmtRocksDB ->
                        withHistoryRocksDB historyDirectory
                            $ \historyRocksDB -> do
                                let csmtDatabase =
                                        mkStakeCSMTDatabase csmtRocksDB
                                    historyDatabase =
                                        mkHistoryDatabase historyRocksDB
                                    queryFinalizedHistory = do
                                        epochRoot <-
                                            expectJust
                                                "expected finalized epoch CSMT root"
                                                =<< runTransactionUnguarded
                                                    csmtDatabase
                                                    ( queryEpochRoot
                                                        finalizedEpoch
                                                    )
                                        (credentialCoin, credentialProof) <-
                                            expectJust
                                                "expected finalized credential proof"
                                                =<< runTransactionUnguarded
                                                    csmtDatabase
                                                    ( buildCredentialProof
                                                        finalizedEpoch
                                                        finalizedCredential
                                                    )
                                        historyRoot <-
                                            expectJust
                                                "expected finalized history root"
                                                =<< runTransactionUnguarded
                                                    historyDatabase
                                                    queryHistoryRoot
                                        historyLeaf <-
                                            expectJust
                                                "expected finalized history leaf"
                                                =<< runTransactionUnguarded
                                                    historyDatabase
                                                    ( queryHistoryLeaf
                                                        finalizedEpoch
                                                    )
                                        (proofLeaf, historyProof) <-
                                            expectJust
                                                "expected finalized history proof"
                                                =<< runTransactionUnguarded
                                                    historyDatabase
                                                    ( buildEpochRootProof
                                                        finalizedEpoch
                                                    )
                                        historyLeaf `shouldBe` epochRoot
                                        proofLeaf `shouldBe` epochRoot
                                        let observation =
                                                FinalizedHistoryObservation
                                                    { finalizedEpochRoot =
                                                        epochRoot
                                                    , finalizedCredentialCoin =
                                                        credentialCoin
                                                    , finalizedCredentialProof =
                                                        credentialProof
                                                    , finalizedHistoryRoot =
                                                        historyRoot
                                                    , finalizedHistoryLeaf =
                                                        historyLeaf
                                                    , finalizedHistoryProof =
                                                        historyProof
                                                    }
                                        verifyFinalizedHistoryObservation
                                            observation
                                            `shouldBe` True
                                        pure observation
                                builtRoot <-
                                    expectJust
                                        "expected non-empty finalized CSMT"
                                        =<< runTransactionUnguarded
                                            csmtDatabase
                                            ( buildEpochCSMT
                                                finalizedEpoch
                                                finalizedSnapshot
                                            )
                                _historyRoot <-
                                    runTransactionUnguarded historyDatabase
                                        $ finalizeEpochRoot
                                            finalizedEpoch
                                            builtRoot
                                beforeRollbackHistory <-
                                    queryFinalizedHistory
                                action
                                    beforeRollbackHistory
                                    queryFinalizedHistory

verifyFinalizedHistoryObservation
    :: FinalizedHistoryObservation -> Bool
verifyFinalizedHistoryObservation FinalizedHistoryObservation{..} =
    finalizedHistoryLeaf == finalizedEpochRoot
        && verifyCredentialProof
            finalizedEpochRoot
            finalizedCredential
            finalizedCredentialCoin
            finalizedCredentialProof
        && verifyEpochRootProof
            finalizedHistoryRoot
            finalizedEpoch
            finalizedHistoryLeaf
            finalizedHistoryProof

expectJust :: String -> Maybe a -> IO a
expectJust _ (Just value) =
    pure value
expectJust context Nothing =
    fail context

finalizedEpoch :: EpochNo
finalizedEpoch = EpochNo 42

finalizedSnapshot :: StakeSnapshot
finalizedSnapshot =
    StakeSnapshot
        { stakeSnapshotStake =
            Map.fromList
                [ (finalizedCredential, Coin 10)
                , (otherFinalizedCredential, Coin 20)
                , (thirdFinalizedCredential, Coin 30)
                ]
        , stakeSnapshotTotalStake = Coin 60
        }

finalizedCredential :: Credential Staking
finalizedCredential = testCredential 7

otherFinalizedCredential :: Credential Staking
otherFinalizedCredential = testCredential 8

thirdFinalizedCredential :: Credential Staking
thirdFinalizedCredential = testCredential 9

testCredential :: Word -> Credential Staking
testCredential byte =
    case hashFromBytes $ BS.replicate 28 $ fromIntegral byte of
        Nothing -> error "invalid deterministic key hash bytes"
        Just keyHash -> KeyHashObj $ KeyHash keyHash

rollbackRunner
    :: [Fetched]
    -> HeaderPoint
    -> ReplayChainSyncRunner
rollbackRunner fetchedBlocks rollbackPoint _ _ _ _ _ Intersector{intersectFound} points = do
    assertOriginStart points
    follower0 <- intersectFound $ Network.Point Network.Point.Origin
    case fetchedBlocks of
        [fetched0, fetched1, fetched2, fetched3, fetched4] -> do
            follower1 <- rollForward follower0 fetched0 $ fetchedTip fetched0
            follower2 <- rollForward follower1 fetched1 $ fetchedTip fetched1
            follower3 <- rollForward follower2 fetched2 $ fetchedTip fetched2
            follower4 <- rollForward follower3 fetched3 $ fetchedTip fetched3
            recoveredFollower <-
                expectProgress "rollback to retained devnet point"
                    =<< rollBackward follower4 rollbackPoint
            follower5 <-
                rollForward recoveredFollower fetched3 $ fetchedTip fetched3
            _follower6 <-
                rollForward follower5 fetched4 $ fetchedTip fetched4
            pure $ Right ()
        other ->
            fail
                $ "expected exactly five fetched blocks, got "
                    <> show (length other)

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
