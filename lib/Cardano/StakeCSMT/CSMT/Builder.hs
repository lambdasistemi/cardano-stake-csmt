{- |
Module      : Cardano.StakeCSMT.CSMT.Builder
Description : Per-epoch stake CSMT builder and inclusion proofs.

Transaction-level helpers for building stake CSMTs from ledger snapshots and
querying/verifying credential stake inclusion proofs.
-}
module Cardano.StakeCSMT.CSMT.Builder
    ( CredentialProof
    , buildCredentialProof
    , buildEpochCSMT
    , queryEpochRoot
    , verifyCredentialProof
    )
where

import CSMT.Hashes
    ( Hash
    , byteStringToKey
    , hashHashing
    , mkHash
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
import Cardano.Ledger.Coin
    ( Coin
    )
import Cardano.Ledger.Credential
    ( Credential
    )
import Cardano.Ledger.Keys
    ( KeyRole (Staking)
    )
import Cardano.Slotting.Slot
    ( EpochNo
    )
import Cardano.StakeCSMT.CSMT.Codecs
    ( EpochRoot (..)
    , coinCodec
    , credentialCodec
    , epochPrefix
    )
import Cardano.StakeCSMT.CSMT.Columns
    ( Columns (..)
    )
import Cardano.StakeCSMT.Ledger.StakeSnapshot
    ( StakeSnapshot (..)
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
import Data.Map.Strict qualified as Map
import Database.KV.Transaction
    ( Transaction
    , insert
    , query
    )

type CredentialProof = InclusionProof Hash

buildEpochCSMT
    :: (Monad m)
    => EpochNo
    -> StakeSnapshot
    -> Transaction m cf Columns ops (Maybe EpochRoot)
buildEpochCSMT epoch StakeSnapshot{stakeSnapshotStake, stakeSnapshotTotalStake}
    | Map.null stakeSnapshotStake = pure Nothing
    | otherwise = do
        CSMT.insertingBatch
            (epochPrefix epoch)
            stakeFromKV
            hashHashing
            SnapshotCol
            TreeCol
            [ ((epoch, credential), coin)
            | (credential, coin) <- Map.toList stakeSnapshotStake
            ]
        mRootHash <- CSMT.root hashHashing TreeCol (epochPrefix epoch)
        case mRootHash of
            Nothing -> pure Nothing
            Just epochRootHash -> do
                let epochRoot =
                        EpochRoot
                            { epochRootHash
                            , epochRootTotalStake = stakeSnapshotTotalStake
                            }
                insert RootCol epoch epochRoot
                pure $ Just epochRoot

queryEpochRoot
    :: EpochNo
    -> Transaction m cf Columns ops (Maybe EpochRoot)
queryEpochRoot =
    query RootCol

buildCredentialProof
    :: (Monad m)
    => EpochNo
    -> Credential Staking
    -> Transaction m cf Columns ops (Maybe (Coin, CredentialProof))
buildCredentialProof epoch credential = do
    let pfx = epochPrefix epoch
        key = (epoch, credential)
    mProof <-
        CSMT.buildInclusionProof
            pfx
            stakeFromKV
            SnapshotCol
            TreeCol
            key
    case mProof of
        Just proof -> pure $ Just proof
        Nothing -> buildPrefixedCredentialProof pfx key

verifyCredentialProof
    :: EpochRoot
    -> Credential Staking
    -> Coin
    -> CredentialProof
    -> Bool
verifyCredentialProof EpochRoot{epochRootHash} credential coin proof =
    proofKey proof == credentialToKey credential
        && proofValue proof == coinToHash coin
        && CSMT.verifyInclusionProof hashHashing epochRootHash proof

stakeFromKV :: FromKV (EpochNo, Credential Staking) Coin Hash
stakeFromKV =
    FromKV
        { isoK =
            iso
                (credentialToKey . snd)
                ( const
                    $ error
                        "stakeFromKV: inverse CSMT key decoding is internal-only"
                )
        , fromV = coinToHash
        , treePrefix = const []
        }

credentialToKey :: Credential Staking -> Key
credentialToKey =
    byteStringToKey . review credentialCodec

coinToHash :: Coin -> Hash
coinToHash =
    mkHash . review coinCodec

buildPrefixedCredentialProof
    :: (Monad m)
    => Key
    -> (EpochNo, Credential Staking)
    -> Transaction m cf Columns ops (Maybe (Coin, CredentialProof))
buildPrefixedCredentialProof pfx key =
    runMaybeT $ do
        coin <- MaybeT $ query SnapshotCol key
        let proofKey = treePrefix stakeFromKV coin <> view (isoK stakeFromKV) key
            proofValue = fromV stakeFromKV coin
        Indirect rootJump _ <- MaybeT $ query TreeCol pfx
        guard $ rootJump `isPrefixOf` proofKey
        proofSteps <- go rootJump $ drop (length rootJump) proofKey
        pure
            ( coin
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
            MaybeT $ query TreeCol $ pfx <> pathFromRoot <> [direction]
        guard $ jump `isPrefixOf` remainingKey
        stepSibling <-
            MaybeT
                $ query TreeCol
                $ pfx <> pathFromRoot <> [oppositeDirection direction]
        let step =
                ProofStep
                    { stepConsumed = 1 + length jump
                    , stepSibling
                    }
        (step :)
            <$> go
                (pathFromRoot <> (direction : jump))
                (drop (length jump) remainingKey)
