{- |
Module      : Cardano.StakeCSMT.Indexer
Description : Epoch boundary stake snapshot indexing primitives.

Public writer primitives for storing finalized epoch stake snapshots into the
shared stake and history databases.
-}
module Cardano.StakeCSMT.Indexer
    ( IndexerError (..)
    , IndexedEpoch (..)
    , EpochBoundaryHook
    , handleEpochBoundarySnapshot
    , indexStakeSnapshot
    , runIndexer
    , runIndexerWith
    , runIndexerWithStore
    , withIndexer
    )
where

import Cardano.Slotting.Slot
    ( EpochNo (..)
    )
import Cardano.StakeCSMT.CSMT.Builder
    ( buildEpochCSMT
    )
import Cardano.StakeCSMT.CSMT.Codecs
    ( EpochRoot
    , Hash
    )
import Cardano.StakeCSMT.CSMT.Columns qualified as Stake
import Cardano.StakeCSMT.History.Builder
    ( finalizeEpochRoot
    )
import Cardano.StakeCSMT.History.Columns qualified as History
import Cardano.StakeCSMT.Ledger.Config
    ( LedgerConfigBundle
    )
import Cardano.StakeCSMT.Ledger.Replay
    ( EpochTransition
    , ReplayChainSyncRunner
    , ReplayCheckpointConfig
    , ReplayFollowerConfig
    , ReplayState (..)
    , defaultReplayChainSyncRunner
    , replayBlock
    , runReplayFollowerWithCheckpoints
    )
import Cardano.StakeCSMT.Ledger.StakeSnapshot
    ( StakeSnapshot
    , StakeSnapshotError (..)
    , stakeSnapshotFromLedgerState
    )
import Cardano.StakeCSMT.Store.Columns qualified as Store
import Control.Concurrent
    ( forkIO
    , killThread
    )
import Control.Exception
    ( Exception
    , SomeException
    , bracket
    , throwIO
    , try
    )
import Control.Monad
    ( join
    )
import Data.Bifunctor
    ( first
    , second
    )
import Data.IORef
    ( newIORef
    , readIORef
    , writeIORef
    )
import Database.KV.Database
    ( Column (..)
    , Database (..)
    , getColumn
    )
import Database.KV.Transaction
    ( DMap
    , DSum ((:=>))
    , GCompare
    , fromList
    , mapColumns
    , runTransactionUnguarded
    )

-- | Errors that make the indexer fail closed.
newtype IndexerError
    = IndexerSnapshotError StakeSnapshotError
    deriving stock (Eq, Show)

instance Exception IndexerError

-- | Stores written for one indexed epoch boundary.
data IndexedEpoch = IndexedEpoch
    { indexedEpoch :: !EpochNo
    -- ^ Epoch whose stake snapshot was indexed.
    , indexedEpochRoot :: !EpochRoot
    -- ^ Root of the per-epoch stake CSMT.
    , indexedHistoryRoot :: !Hash
    -- ^ Current history accumulator root after finalization.
    }
    deriving stock (Eq, Show)

-- | Callback invoked after an observed epoch boundary has been handled.
type EpochBoundaryHook =
    EpochTransition -> Maybe IndexedEpoch -> IO ()

-- | Handle an epoch-boundary snapshot result, skipping Byron-era boundaries.
handleEpochBoundarySnapshot
    :: (EpochNo -> StakeSnapshot -> IO (Maybe IndexedEpoch))
    -> EpochNo
    -> Either StakeSnapshotError StakeSnapshot
    -> IO (Maybe IndexedEpoch)
handleEpochBoundarySnapshot indexSnapshot epoch snapshotResult =
    case snapshotResult of
        Left err
            | err == StakeSnapshotByronEra ->
                pure Nothing
            | otherwise ->
                throwIO $ IndexerSnapshotError err
        Right snapshot ->
            indexSnapshot epoch snapshot

-- | Write a ledger stake snapshot into the stake and history stores.
indexStakeSnapshot
    :: Database IO storeCf Store.Columns storeOps
    -> EpochNo
    -> StakeSnapshot
    -> IO (Maybe IndexedEpoch)
indexStakeSnapshot storeDb epoch snapshot =
    runTransactionUnguarded storeDb $ do
        mEpochRoot <-
            mapColumns Store.StakeColumn
                $ buildEpochCSMT epoch snapshot
        traverse finalizeHistory mEpochRoot
  where
    finalizeHistory epochRoot = do
        historyRoot <-
            mapColumns Store.HistoryColumn
                $ finalizeEpochRoot epoch epochRoot
        pure
            IndexedEpoch
                { indexedEpoch = epoch
                , indexedEpochRoot = epochRoot
                , indexedHistoryRoot = historyRoot
                }

-- | Run the checkpoint-backed indexer using the default ChainSync runner.
runIndexer
    :: LedgerConfigBundle
    -> Database IO storeCf Store.Columns storeOps
    -> ReplayFollowerConfig
    -> ReplayCheckpointConfig
    -> Maybe EpochBoundaryHook
    -> IO (Either SomeException ())
runIndexer =
    runIndexerWithStore defaultReplayChainSyncRunner

-- | Run the checkpoint-backed indexer over the unified store.
runIndexerWithStore
    :: ReplayChainSyncRunner
    -> LedgerConfigBundle
    -> Database IO storeCf Store.Columns storeOps
    -> ReplayFollowerConfig
    -> ReplayCheckpointConfig
    -> Maybe EpochBoundaryHook
    -> IO (Either SomeException ())
runIndexerWithStore chainSyncRunner bundle storeDb =
    runIndexerWithIndexing
        chainSyncRunner
        bundle
        (indexStakeSnapshot storeDb)

-- | Run the checkpoint-backed indexer with an injected ChainSync runner.
runIndexerWith
    :: ReplayChainSyncRunner
    -> LedgerConfigBundle
    -> Database IO stakeCf Stake.Columns stakeOps
    -> Database IO historyCf History.Columns historyOps
    -> ReplayFollowerConfig
    -> ReplayCheckpointConfig
    -> Maybe EpochBoundaryHook
    -> IO (Either SomeException ())
runIndexerWith
    chainSyncRunner
    bundle
    stakeDb
    historyDb =
        runIndexerWithIndexing
            chainSyncRunner
            bundle
            (indexStakeSnapshot $ mkSplitStoreDatabase stakeDb historyDb)

runIndexerWithIndexing
    :: ReplayChainSyncRunner
    -> LedgerConfigBundle
    -> (EpochNo -> StakeSnapshot -> IO (Maybe IndexedEpoch))
    -> ReplayFollowerConfig
    -> ReplayCheckpointConfig
    -> Maybe EpochBoundaryHook
    -> IO (Either SomeException ())
runIndexerWithIndexing
    chainSyncRunner
    bundle
    indexSnapshot
    followerConfig
    checkpointConfig
    hook = do
        result <-
            try
                $ runReplayFollowerWithCheckpoints
                    chainSyncRunner
                    replayAndIndex
                    bundle
                    followerConfig
                    checkpointConfig
        pure
            $ join
                ( result
                    :: Either SomeException (Either SomeException ())
                )
      where
        replayAndIndex state block = do
            transitionRef <- newIORef Nothing
            nextState <-
                replayBlock
                    bundle
                    (writeIORef transitionRef . Just)
                    state
                    block
            mTransition <- readIORef transitionRef
            case mTransition of
                Nothing ->
                    pure nextState
                Just transition -> do
                    indexed <-
                        handleEpochBoundarySnapshot
                            indexSnapshot
                            (EpochNo $ replayStateLastEpoch nextState)
                            ( stakeSnapshotFromLedgerState
                                $ replayStateLedgerState nextState
                            )
                    maybe
                        (pure ())
                        (\notify -> notify transition indexed)
                        hook
                    pure nextState

-- | Run an action while the indexer thread is active.
withIndexer
    :: LedgerConfigBundle
    -> Database IO storeCf Store.Columns storeOps
    -> ReplayFollowerConfig
    -> ReplayCheckpointConfig
    -> Maybe EpochBoundaryHook
    -> IO a
    -> IO a
withIndexer
    bundle
    storeDb
    followerConfig
    checkpointConfig
    hook
    action =
        bracket start killThread $ const action
      where
        start =
            forkIO $ do
                result <-
                    runIndexer
                        bundle
                        storeDb
                        followerConfig
                        checkpointConfig
                        hook
                either throwIO pure result

data SplitOp stakeOps historyOps
    = StakeOp stakeOps
    | HistoryOp historyOps

mkSplitStoreDatabase
    :: Database IO stakeCf Stake.Columns stakeOps
    -> Database IO historyCf History.Columns historyOps
    -> Database
        IO
        (Either stakeCf historyCf)
        Store.Columns
        (SplitOp stakeOps historyOps)
mkSplitStoreDatabase stakeDb historyDb =
    Database
        { valueAt = \cf key ->
            case cf of
                Left stakeCf ->
                    valueAt stakeDb stakeCf key
                Right historyCf ->
                    valueAt historyDb historyCf key
        , applyOps = \ops -> do
            let (stakeOps, historyOps) = splitOps ops
            applyOps stakeDb stakeOps
            applyOps historyDb historyOps
        , mkOperation = \cf key value ->
            case cf of
                Left stakeCf ->
                    StakeOp $ mkOperation stakeDb stakeCf key value
                Right historyCf ->
                    HistoryOp $ mkOperation historyDb historyCf key value
        , newIterator = \case
            Left stakeCf ->
                newIterator stakeDb stakeCf
            Right historyCf ->
                newIterator historyDb historyCf
        , columns =
            fromList
                [ Store.StakeColumn Stake.SnapshotCol
                    :=> leftColumnFrom
                        (columns stakeDb)
                        Stake.SnapshotCol
                , Store.StakeColumn Stake.TreeCol
                    :=> leftColumnFrom
                        (columns stakeDb)
                        Stake.TreeCol
                , Store.StakeColumn Stake.RootCol
                    :=> leftColumnFrom
                        (columns stakeDb)
                        Stake.RootCol
                , Store.HistoryColumn History.HistoryLeafCol
                    :=> rightColumnFrom
                        (columns historyDb)
                        History.HistoryLeafCol
                , Store.HistoryColumn History.HistoryTreeCol
                    :=> rightColumnFrom
                        (columns historyDb)
                        History.HistoryTreeCol
                , Store.HistoryColumn History.HistoryRootCol
                    :=> rightColumnFrom
                        (columns historyDb)
                        History.HistoryRootCol
                ]
        , withSnapshot = \action ->
            withSnapshot stakeDb $ \stakeSnapshot ->
                withSnapshot historyDb $ \historySnapshot ->
                    action
                        $ mkSplitStoreDatabase
                            stakeSnapshot
                            historySnapshot
        }
  where
    splitOps =
        foldr
            ( \case
                StakeOp op -> \(stakeOps, historyOps) ->
                    first (op :) (stakeOps, historyOps)
                HistoryOp op -> \(stakeOps, historyOps) ->
                    second (op :) (stakeOps, historyOps)
            )
            ([], [])

leftColumnFrom
    :: DMap Stake.Columns (Column stakeCf)
    -> Stake.Columns c
    -> Column (Either stakeCf historyCf) c
leftColumnFrom stakeColumns selector =
    mapColumn Left
        $ expectColumnIn
            "mkSplitStoreDatabase: stake column not found"
            selector
            stakeColumns

rightColumnFrom
    :: DMap History.Columns (Column historyCf)
    -> History.Columns c
    -> Column (Either stakeCf historyCf) c
rightColumnFrom historyColumns selector =
    mapColumn Right
        $ expectColumnIn
            "mkSplitStoreDatabase: history column not found"
            selector
            historyColumns

expectColumnIn
    :: GCompare columns
    => String
    -> columns c
    -> DMap columns (Column cf)
    -> Column cf c
expectColumnIn message selector availableColumns =
    case getColumn selector availableColumns of
        Just column -> column
        Nothing -> error message

mapColumn :: (cf -> cf') -> Column cf c -> Column cf' c
mapColumn f Column{family, codecs} =
    Column
        { family = f family
        , codecs
        }
