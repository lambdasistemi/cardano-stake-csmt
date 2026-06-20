{- |
Module      : Cardano.StakeCSMT.Ledger.StakeSnapshot
Description : Pure extraction of mark stake snapshots from ledger state.

Project the current Shelley-based Cardano ledger state into credential stake
from the mark snapshot.
-}
module Cardano.StakeCSMT.Ledger.StakeSnapshot
    ( StakeSnapshot (..)
    , StakeSnapshotError (..)
    , stakeSnapshotFromLedgerState
    ) where

import Cardano.Ledger.BaseTypes
    ( NonZero (unNonZero)
    )
import Cardano.Ledger.Coin
    ( Coin
    )
import Cardano.Ledger.Compactible
    ( fromCompact
    )
import Cardano.Ledger.Credential
    ( Credential
    )
import Cardano.Ledger.Keys
    ( KeyRole (Staking)
    )
import Cardano.Ledger.Shelley.LedgerState
    ( NewEpochState
    , esSnapshots
    , nesEs
    )
import Cardano.Ledger.State
    ( ssActiveStake
    , ssStakeMark
    , swdStake
    , unActiveStake
    )
import Cardano.StakeCSMT.Ledger.Config
    ( StakeBlock
    )
import Data.Foldable
    ( fold
    )
import Data.Map.Strict
    ( Map
    )
import Data.Map.Strict qualified as Map
import Data.VMap qualified as VMap
import Ouroboros.Consensus.Cardano.Block
    ( pattern LedgerStateAllegra
    , pattern LedgerStateAlonzo
    , pattern LedgerStateBabbage
    , pattern LedgerStateByron
    , pattern LedgerStateConway
    , pattern LedgerStateDijkstra
    , pattern LedgerStateMary
    , pattern LedgerStateShelley
    )
import Ouroboros.Consensus.Ledger.Basics
    ( ValuesMK
    )
import Ouroboros.Consensus.Ledger.Extended
    ( ExtLedgerState (..)
    )
import Ouroboros.Consensus.Shelley.Ledger
    ( shelleyLedgerState
    )

data StakeSnapshot = StakeSnapshot
    { stakeSnapshotStake :: !(Map (Credential Staking) Coin)
    , stakeSnapshotTotalStake :: !Coin
    }
    deriving stock (Eq, Show)

data StakeSnapshotError
    = StakeSnapshotByronEra
    deriving stock (Eq, Show)

stakeSnapshotFromLedgerState
    :: ExtLedgerState StakeBlock ValuesMK
    -> Either StakeSnapshotError StakeSnapshot
stakeSnapshotFromLedgerState extLedgerState =
    case ledgerState extLedgerState of
        LedgerStateByron _ ->
            Left StakeSnapshotByronEra
        LedgerStateShelley st ->
            Right $ stakeSnapshotFromNewEpochState $ shelleyLedgerState st
        LedgerStateAllegra st ->
            Right $ stakeSnapshotFromNewEpochState $ shelleyLedgerState st
        LedgerStateMary st ->
            Right $ stakeSnapshotFromNewEpochState $ shelleyLedgerState st
        LedgerStateAlonzo st ->
            Right $ stakeSnapshotFromNewEpochState $ shelleyLedgerState st
        LedgerStateBabbage st ->
            Right $ stakeSnapshotFromNewEpochState $ shelleyLedgerState st
        LedgerStateConway st ->
            Right $ stakeSnapshotFromNewEpochState $ shelleyLedgerState st
        LedgerStateDijkstra st ->
            Right $ stakeSnapshotFromNewEpochState $ shelleyLedgerState st

stakeSnapshotFromNewEpochState :: NewEpochState era -> StakeSnapshot
stakeSnapshotFromNewEpochState nes =
    StakeSnapshot
        { stakeSnapshotStake = stakeMap
        , stakeSnapshotTotalStake = fold stakeMap
        }
  where
    activeStake = ssActiveStake $ ssStakeMark $ esSnapshots $ nesEs nes
    stakeMap =
        Map.map (fromCompact . unNonZero . swdStake)
            $ VMap.toMap
            $ unActiveStake activeStake
