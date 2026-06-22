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
    , indexStakeSnapshot
    , runIndexer
    , runIndexerWith
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
    , StakeSnapshotError
    , stakeSnapshotFromLedgerState
    )
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
import Data.IORef
    ( newIORef
    , readIORef
    , writeIORef
    )
import Database.KV.Database
    ( Database
    )
import Database.KV.Transaction
    ( runTransactionUnguarded
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

-- | Write a ledger stake snapshot into the stake and history stores.
indexStakeSnapshot
    :: Database IO stakeCf Stake.Columns stakeOps
    -> Database IO historyCf History.Columns historyOps
    -> EpochNo
    -> StakeSnapshot
    -> IO (Maybe IndexedEpoch)
indexStakeSnapshot stakeDb historyDb epoch snapshot = do
    mEpochRoot <-
        runTransactionUnguarded stakeDb
            $ buildEpochCSMT epoch snapshot
    traverse finalizeHistory mEpochRoot
  where
    finalizeHistory epochRoot = do
        historyRoot <-
            runTransactionUnguarded historyDb
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
    -> Database IO stakeCf Stake.Columns stakeOps
    -> Database IO historyCf History.Columns historyOps
    -> ReplayFollowerConfig
    -> ReplayCheckpointConfig
    -> Maybe EpochBoundaryHook
    -> IO (Either SomeException ())
runIndexer =
    runIndexerWith defaultReplayChainSyncRunner

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
    historyDb
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
                    snapshot <-
                        either
                            (throwIO . IndexerSnapshotError)
                            pure
                            $ stakeSnapshotFromLedgerState
                            $ replayStateLedgerState nextState
                    indexed <-
                        indexStakeSnapshot
                            stakeDb
                            historyDb
                            (EpochNo $ replayStateLastEpoch nextState)
                            snapshot
                    maybe
                        (pure ())
                        (\notify -> notify transition indexed)
                        hook
                    pure nextState

-- | Run an action while the indexer thread is active.
withIndexer
    :: LedgerConfigBundle
    -> Database IO stakeCf Stake.Columns stakeOps
    -> Database IO historyCf History.Columns historyOps
    -> ReplayFollowerConfig
    -> ReplayCheckpointConfig
    -> Maybe EpochBoundaryHook
    -> IO a
    -> IO a
withIndexer
    bundle
    stakeDb
    historyDb
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
                        stakeDb
                        historyDb
                        followerConfig
                        checkpointConfig
                        hook
                either throwIO pure result
