{- |
Module      : Cardano.StakeCSMT.Indexer
Description : Epoch boundary stake snapshot indexing primitives.

Public writer primitives for storing finalized epoch stake snapshots into the
shared stake and history databases.
-}
module Cardano.StakeCSMT.Indexer
    ( IndexedEpoch (..)
    , EpochBoundaryHook
    , indexStakeSnapshot
    )
where

import Cardano.Slotting.Slot
    ( EpochNo
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
import Cardano.StakeCSMT.Ledger.Replay
    ( EpochTransition
    )
import Cardano.StakeCSMT.Ledger.StakeSnapshot
    ( StakeSnapshot
    )
import Database.KV.Database
    ( Database
    )
import Database.KV.Transaction
    ( runTransactionUnguarded
    )

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
