module Cardano.StakeCSMT.Ledger.Replay
    ( EpochTransition (..)
    , ReplayState (..)
    , initialReplayState
    , observeEpochTransition
    , replayBlock
    )
where

import Cardano.Slotting.Slot
    ( SlotNo (..)
    )
import Cardano.StakeCSMT.Ledger.Config
    ( LedgerConfigBundle (..)
    , StakeBlock
    , ledgerConfigEpochAt
    )
import Data.Word
    ( Word64
    )
import Ouroboros.Consensus.Block
    ( blockSlot
    )
import Ouroboros.Consensus.Ledger.Abstract
    ( ComputeLedgerEvents (OmitLedgerEvents)
    , tickThenReapply
    )
import Ouroboros.Consensus.Ledger.Basics
    ( ValuesMK
    )
import Ouroboros.Consensus.Ledger.Extended
    ( ExtLedgerCfg (ExtLedgerCfg)
    , ExtLedgerState
    )
import Ouroboros.Consensus.Ledger.Tables.Utils
    ( applyDiffs
    )

data ReplayState = ReplayState
    { replayStateLedgerState :: !(ExtLedgerState StakeBlock ValuesMK)
    , replayStateLastEpoch :: !Word64
    }

data EpochTransition = EpochTransition
    { epochTransitionPreviousEpoch :: !Word64
    , epochTransitionNewEpoch :: !Word64
    , epochTransitionSlot :: !Word64
    }
    deriving stock (Eq, Show)

initialReplayState :: LedgerConfigBundle -> IO ReplayState
initialReplayState bundle@LedgerConfigBundle{ledgerConfigGenesisState} = do
    genesisEpoch <- ledgerConfigEpochAt bundle 0
    pure
        ReplayState
            { replayStateLedgerState = ledgerConfigGenesisState
            , replayStateLastEpoch = genesisEpoch
            }

observeEpochTransition
    :: Monad m
    => (EpochTransition -> m ())
    -> ReplayState
    -> Word64
    -> Word64
    -> m ReplayState
observeEpochTransition notify state@ReplayState{replayStateLastEpoch} slot epoch
    | replayStateLastEpoch == epoch =
        pure state
    | otherwise = do
        notify
            EpochTransition
                { epochTransitionPreviousEpoch = replayStateLastEpoch
                , epochTransitionNewEpoch = epoch
                , epochTransitionSlot = slot
                }
        pure state{replayStateLastEpoch = epoch}

replayBlock
    :: LedgerConfigBundle
    -> (EpochTransition -> IO ())
    -> ReplayState
    -> StakeBlock
    -> IO ReplayState
replayBlock bundle@LedgerConfigBundle{ledgerConfigTopLevelConfig} notify state block = do
    let previousLedgerState = replayStateLedgerState state
        diffLedgerState =
            tickThenReapply
                OmitLedgerEvents
                (ExtLedgerCfg ledgerConfigTopLevelConfig)
                block
                previousLedgerState
        nextLedgerState = applyDiffs previousLedgerState diffLedgerState
        SlotNo slot = blockSlot block
    epoch <- ledgerConfigEpochAt bundle slot
    observeEpochTransition
        notify
        state{replayStateLedgerState = nextLedgerState}
        slot
        epoch
