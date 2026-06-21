{- |
Module      : Cardano.StakeCSMT.History.Builder
Description : Transaction-level history accumulator builder and proofs.

Helpers for finalizing epoch roots into the history accumulator and
querying/verifying epoch-root inclusion proofs.
-}
module Cardano.StakeCSMT.History.Builder
    ( EpochRootProof
    , buildEpochRootProof
    , finalizeEpochRoot
    , queryHistoryLeaf
    , queryHistoryRoot
    , verifyEpochRootProof
    )
where

import CSMT.Hashes
    ( Hash
    , byteStringToKey
    , hashHashing
    )
import CSMT.Insertion qualified as CSMT
import CSMT.Interface
    ( FromKV (..)
    , Indirect (..)
    , Key
    , oppositeDirection
    )
import CSMT.Interface qualified as CSMT
import CSMT.Proof.Insertion
    ( InclusionProof (..)
    , ProofStep (..)
    )
import CSMT.Proof.Insertion qualified as CSMT
import Cardano.Slotting.Slot
    ( EpochNo
    )
import Cardano.StakeCSMT.CSMT.Codecs
    ( EpochRoot
    , epochNoCodec
    )
import Cardano.StakeCSMT.History.Codecs
    ( historyLeafHash
    , historyPrefix
    )
import Cardano.StakeCSMT.History.Columns
    ( Columns (..)
    )
import Control.Lens
    ( iso
    , review
    , view
    )
import Control.Monad
    ( guard
    )
import Control.Monad.Trans.Maybe
    ( MaybeT (..)
    , runMaybeT
    )
import Data.List
    ( isPrefixOf
    )
import Database.KV.Transaction
    ( Transaction
    , insert
    , query
    )

type EpochRootProof = InclusionProof Hash

finalizeEpochRoot
    :: (Monad m)
    => EpochNo
    -> EpochRoot
    -> Transaction m cf Columns ops Hash
finalizeEpochRoot epoch epochRoot = do
    CSMT.insertingBatch
        historyPrefix
        historyFromKV
        hashHashing
        HistoryLeafCol
        HistoryTreeCol
        [(epoch, epochRoot)]
    mRootHash <- CSMT.root hashHashing HistoryTreeCol historyPrefix
    case mRootHash of
        Nothing ->
            error
                "finalizeEpochRoot: inserted history leaf but root is missing"
        Just historyRoot -> do
            insert HistoryRootCol () historyRoot
            pure historyRoot

queryHistoryLeaf
    :: EpochNo
    -> Transaction m cf Columns ops (Maybe EpochRoot)
queryHistoryLeaf =
    query HistoryLeafCol

queryHistoryRoot
    :: Transaction m cf Columns ops (Maybe Hash)
queryHistoryRoot =
    query HistoryRootCol ()

buildEpochRootProof
    :: (Monad m)
    => EpochNo
    -> Transaction m cf Columns ops (Maybe (EpochRoot, EpochRootProof))
buildEpochRootProof epoch = do
    mProof <-
        CSMT.buildInclusionProof
            historyPrefix
            historyFromKV
            HistoryLeafCol
            HistoryTreeCol
            epoch
    case mProof of
        Just proof -> pure $ Just proof
        Nothing -> buildPrefixedEpochRootProof epoch

verifyEpochRootProof
    :: Hash
    -> EpochNo
    -> EpochRoot
    -> EpochRootProof
    -> Bool
verifyEpochRootProof historyRoot epoch epochRoot proof =
    proofKey proof == epochToKey epoch
        && proofValue proof == historyLeafHash epochRoot
        && CSMT.verifyInclusionProof hashHashing historyRoot proof

historyFromKV :: FromKV EpochNo EpochRoot Hash
historyFromKV =
    FromKV
        { isoK =
            iso
                epochToKey
                ( const
                    $ error
                        "historyFromKV: inverse CSMT key decoding is internal-only"
                )
        , fromV = historyLeafHash
        , treePrefix = const []
        }

epochToKey :: EpochNo -> Key
epochToKey =
    byteStringToKey . review epochNoCodec

buildPrefixedEpochRootProof
    :: (Monad m)
    => EpochNo
    -> Transaction m cf Columns ops (Maybe (EpochRoot, EpochRootProof))
buildPrefixedEpochRootProof epoch =
    runMaybeT $ do
        epochRoot <- MaybeT $ query HistoryLeafCol epoch
        let proofKey =
                treePrefix historyFromKV epochRoot
                    <> view (isoK historyFromKV) epoch
            proofValue = fromV historyFromKV epochRoot
        Indirect rootJump _ <- MaybeT $ query HistoryTreeCol historyPrefix
        guard $ rootJump `isPrefixOf` proofKey
        proofSteps <- go rootJump $ drop (length rootJump) proofKey
        pure
            ( epochRoot
            , InclusionProof
                { proofKey
                , proofValue
                , proofSteps = reverse proofSteps
                , proofRootJump = rootJump
                }
            )
  where
    go _ [] = pure []
    go pathFromRoot (direction : remainingKey) = do
        Indirect jump _ <-
            MaybeT
                $ query HistoryTreeCol
                $ historyPrefix <> pathFromRoot <> [direction]
        guard $ jump `isPrefixOf` remainingKey
        stepSibling <-
            MaybeT
                $ query HistoryTreeCol
                $ historyPrefix <> pathFromRoot <> [oppositeDirection direction]
        let step =
                ProofStep
                    { stepConsumed = 1 + length jump
                    , stepSibling
                    }
        (step :)
            <$> go
                (pathFromRoot <> (direction : jump))
                (drop (length jump) remainingKey)
