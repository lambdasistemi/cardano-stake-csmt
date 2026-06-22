module Cardano.StakeCSMT.Ledger.Replay
    ( EpochTransition (..)
    , ReplayCheckpointConfig (..)
    , ReplayState (..)
    , ReplayChainSyncRunner
    , ReplayFollowerConfig (..)
    , defaultReplayChainSyncRunner
    , initialReplayState
    , observeEpochTransition
    , replayBlock
    , runReplayFollower
    , runReplayFollowerWithCheckpoints
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
import Cardano.StakeCSMT.Ledger.Checkpoint
    ( CheckpointPoint (..)
    , ReplayCheckpoint (..)
    , ReplayTail
    , appendReplayTail
    , checkpointPointFromHeaderPoint
    , emptyReplayTail
    , listReplayCheckpoints
    , loadReplayCheckpoint
    , nearestCheckpointAtOrBefore
    , recoverReplayTail
    , saveReplayCheckpoint
    , truncateReplayTailAfter
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
import Control.Monad
    ( foldM
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

data ReplayCheckpointConfig = ReplayCheckpointConfig
    { replayCheckpointDirectory :: !FilePath
    , replayCheckpointTailLimit :: !Int
    , replayCheckpointCadence :: !Word64
    , replayCheckpointSaveState
        :: !(ReplayCheckpoint -> ReplayState -> IO ())
    , replayCheckpointLoadState
        :: !(ReplayCheckpoint -> IO (Maybe ReplayState))
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

runReplayFollowerWithCheckpoints
    :: ReplayChainSyncRunner
    -> (ReplayState -> StakeBlock -> IO ReplayState)
    -> LedgerConfigBundle
    -> ReplayFollowerConfig
    -> ReplayCheckpointConfig
    -> IO (Either SomeException ())
runReplayFollowerWithCheckpoints
    chainSyncRunner
    replayAction
    bundle
    ReplayFollowerConfig
        { replayFollowerSocketPath
        , replayFollowerNetworkMagic
        , replayFollowerByronEpochSlots
        }
    checkpointConfig =
        chainSyncRunner
            (EpochSlots replayFollowerByronEpochSlots)
            replayFollowerNetworkMagic
            replayFollowerSocketPath
            nullTracer
            nullTracer
            (mkCheckpointReplayIntersector bundle replayAction checkpointConfig)
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
        , rollBackward = \case
            Network.Point Network.Point.Origin ->
                pure $ Progress $ mkReplayFollower intersector replayAction state
            Network.Point (Network.Point.At _) ->
                pure $ Reset intersector
        }

mkCheckpointReplayIntersector
    :: LedgerConfigBundle
    -> (ReplayState -> StakeBlock -> IO ReplayState)
    -> ReplayCheckpointConfig
    -> Intersector HeaderPoint Network.SlotNo Fetched
mkCheckpointReplayIntersector bundle replayAction checkpointConfig = intersector
  where
    intersector =
        Intersector
            { intersectFound = \_point ->
                mkCheckpointReplayFollower
                    intersector
                    replayAction
                    checkpointConfig
                    <$> initialReplayState bundle
                    <*> pure emptyReplayTail
            , intersectNotFound =
                pure (intersector, [originPoint])
            }

mkCheckpointReplayFollower
    :: Intersector HeaderPoint Network.SlotNo Fetched
    -> (ReplayState -> StakeBlock -> IO ReplayState)
    -> ReplayCheckpointConfig
    -> ReplayState
    -> ReplayTail
    -> Follower HeaderPoint Network.SlotNo Fetched
mkCheckpointReplayFollower intersector replayAction checkpointConfig state replayTail =
    Follower
        { rollForward = \fetched _tip -> do
            nextState <- replayAction state (fetchedBlock fetched)
            saveReplayCheckpointAt checkpointConfig fetched nextState
            let nextTail =
                    appendReplayTail
                        (replayCheckpointTailLimit checkpointConfig)
                        fetched
                        replayTail
            pure
                $ mkCheckpointReplayFollower
                    intersector
                    replayAction
                    checkpointConfig
                    nextState
                    nextTail
        , rollBackward = \case
            Network.Point Network.Point.Origin ->
                pure
                    $ Progress
                    $ mkCheckpointReplayFollower
                        intersector
                        replayAction
                        checkpointConfig
                        state
                        replayTail
            point -> do
                recovery <-
                    recoverReplayState
                        replayAction
                        checkpointConfig
                        replayTail
                        point
                case recovery of
                    Nothing ->
                        pure $ Reset intersector
                    Just (recoveredState, recoveredTail) ->
                        pure
                            $ Progress
                            $ mkCheckpointReplayFollower
                                intersector
                                replayAction
                                checkpointConfig
                                recoveredState
                                recoveredTail
        }

saveReplayCheckpointAt
    :: ReplayCheckpointConfig
    -> Fetched
    -> ReplayState
    -> IO ()
saveReplayCheckpointAt checkpointConfig fetched state =
    case checkpointPointFromHeaderPoint $ fetchedPoint fetched of
        CheckpointOrigin ->
            pure ()
        point@(CheckpointAtBlock slot)
            | shouldSaveReplayCheckpoint
                (replayCheckpointCadence checkpointConfig)
                slot -> do
                let checkpoint =
                        ReplayCheckpoint
                            { replayCheckpointPoint = point
                            , replayCheckpointFinalizedEpoch =
                                replayStateLastEpoch state
                            , replayCheckpointObservedEpoch =
                                replayStateLastEpoch state
                            }
                _ <-
                    saveReplayCheckpoint
                        (replayCheckpointDirectory checkpointConfig)
                        checkpoint
                replayCheckpointSaveState checkpointConfig checkpoint state
            | otherwise ->
                pure ()

shouldSaveReplayCheckpoint :: Word64 -> Word64 -> Bool
shouldSaveReplayCheckpoint cadence slot =
    cadence > 0 && slot `mod` cadence == 0

recoverReplayState
    :: (ReplayState -> StakeBlock -> IO ReplayState)
    -> ReplayCheckpointConfig
    -> ReplayTail
    -> HeaderPoint
    -> IO (Maybe (ReplayState, ReplayTail))
recoverReplayState replayAction checkpointConfig replayTail rollbackPoint = do
    let target = checkpointPointFromHeaderPoint rollbackPoint
    checkpointPoints <-
        listReplayCheckpoints $ replayCheckpointDirectory checkpointConfig
    case nearestCheckpointAtOrBefore checkpointPoints target of
        Nothing ->
            pure Nothing
        Just checkpointPoint -> do
            checkpointResult <-
                loadReplayCheckpoint
                    (replayCheckpointDirectory checkpointConfig)
                    checkpointPoint
            case checkpointResult of
                Left _err ->
                    pure Nothing
                Right checkpoint -> do
                    checkpointState <-
                        replayCheckpointLoadState checkpointConfig checkpoint
                    case checkpointState of
                        Nothing ->
                            pure Nothing
                        Just state ->
                            recoverFromCheckpoint
                                replayAction
                                replayTail
                                target
                                checkpoint
                                state

recoverFromCheckpoint
    :: (ReplayState -> StakeBlock -> IO ReplayState)
    -> ReplayTail
    -> CheckpointPoint
    -> ReplayCheckpoint
    -> ReplayState
    -> IO (Maybe (ReplayState, ReplayTail))
recoverFromCheckpoint replayAction replayTail target checkpoint state =
    case recoverReplayTail
        (replayCheckpointPoint checkpoint)
        target
        replayTail of
        Nothing ->
            pure Nothing
        Just fetchedBlocks -> do
            recoveredState <-
                foldM
                    ( \current fetched ->
                        replayAction current $ fetchedBlock fetched
                    )
                    state
                    fetchedBlocks
            pure
                $ Just
                    ( recoveredState
                    , truncateReplayTailAfter target replayTail
                    )

originPoint :: HeaderPoint
originPoint =
    Network.Point Network.Point.Origin
