module Cardano.StakeCSMT.Ledger.Replay
    ( EpochTransition (..)
    , ReplayState (..)
    , ReplayChainSyncRunner
    , ReplayFollowerConfig (..)
    , defaultReplayChainSyncRunner
    , initialReplayState
    , observeEpochTransition
    , replayBlock
    , runReplayFollower
    , runReplayFollowerWith
    )
where

import Cardano.Chain.Slotting
    ( EpochSlots (..)
    )
import Cardano.Node.Client.N2C.ChainSync
    ( Fetched (..)
    , HeaderPoint
    , mkChainSyncN2C
    , runChainSyncN2C
    )
import Cardano.Slotting.Slot
    ( SlotNo (..)
    )
import Cardano.StakeCSMT.Ledger.Config
    ( LedgerConfigBundle (..)
    , StakeBlock
    , ledgerConfigEpochAt
    )
import ChainFollower
    ( Follower (..)
    , Intersector (..)
    , ProgressOrRewind (..)
    )
import Control.Exception
    ( SomeException
    )
import Control.Tracer
    ( Tracer
    , nullTracer
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
import Ouroboros.Network.Block qualified as Network
import Ouroboros.Network.Magic
    ( NetworkMagic
    )
import Ouroboros.Network.Point qualified as Network.Point

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

data ReplayFollowerConfig = ReplayFollowerConfig
    { replayFollowerSocketPath :: !FilePath
    , replayFollowerNetworkMagic :: !NetworkMagic
    , replayFollowerByronEpochSlots :: !Word64
    }

type ReplayChainSyncRunner =
    EpochSlots
    -> NetworkMagic
    -> FilePath
    -> Tracer IO StakeBlock
    -> Tracer IO Network.SlotNo
    -> Intersector HeaderPoint Network.SlotNo Fetched
    -> [HeaderPoint]
    -> IO (Either SomeException ())

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

runReplayFollower
    :: LedgerConfigBundle
    -> (EpochTransition -> IO ())
    -> ReplayFollowerConfig
    -> IO (Either SomeException ())
runReplayFollower bundle notify =
    runReplayFollowerWith
        defaultReplayChainSyncRunner
        (replayBlock bundle notify)
        bundle

runReplayFollowerWith
    :: ReplayChainSyncRunner
    -> (ReplayState -> StakeBlock -> IO ReplayState)
    -> LedgerConfigBundle
    -> ReplayFollowerConfig
    -> IO (Either SomeException ())
runReplayFollowerWith
    chainSyncRunner
    replayAction
    bundle
    ReplayFollowerConfig
        { replayFollowerSocketPath
        , replayFollowerNetworkMagic
        , replayFollowerByronEpochSlots
        } =
        chainSyncRunner
            (EpochSlots replayFollowerByronEpochSlots)
            replayFollowerNetworkMagic
            replayFollowerSocketPath
            nullTracer
            nullTracer
            (mkReplayIntersector bundle replayAction)
            [originPoint]

defaultReplayChainSyncRunner :: ReplayChainSyncRunner
defaultReplayChainSyncRunner
    epochSlots
    magic
    socketPath
    blockTracer
    tipTracer
    intersector
    points =
        runChainSyncN2C
            epochSlots
            magic
            socketPath
            (mkChainSyncN2C blockTracer tipTracer intersector points)

mkReplayIntersector
    :: LedgerConfigBundle
    -> (ReplayState -> StakeBlock -> IO ReplayState)
    -> Intersector HeaderPoint Network.SlotNo Fetched
mkReplayIntersector bundle replayAction = intersector
  where
    intersector =
        Intersector
            { intersectFound = \_point ->
                mkReplayFollower intersector replayAction
                    <$> initialReplayState bundle
            , intersectNotFound =
                pure (intersector, [originPoint])
            }

mkReplayFollower
    :: Intersector HeaderPoint Network.SlotNo Fetched
    -> (ReplayState -> StakeBlock -> IO ReplayState)
    -> ReplayState
    -> Follower HeaderPoint Network.SlotNo Fetched
mkReplayFollower intersector replayAction state =
    Follower
        { rollForward = \fetched _tip -> do
            nextState <- replayAction state (fetchedBlock fetched)
            pure $ mkReplayFollower intersector replayAction nextState
        , rollBackward = \_point ->
            pure $ Reset intersector
        }

originPoint :: HeaderPoint
originPoint =
    Network.Point Network.Point.Origin
