{- |
Module      : Cardano.StakeCSMT.HTTP.Query
Description : Transaction-backed query adapters for HTTP responses.

Adapts the stake CSMT and history builders to the HTTP wire response types.
-}
module Cardano.StakeCSMT.HTTP.Query
    ( queryHistoricalProof
    , queryLatestProof
    , queryEpochRoots
    , querySignedLatestHeader
    , queryCurrentHistoryRoot
    ) where

import CSMT.Hashes
    ( renderProof
    )
import Cardano.Crypto.DSIGN.Class
    ( SignKeyDSIGN
    )
import Cardano.Crypto.DSIGN.Ed25519
    ( Ed25519DSIGN
    )
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
import Cardano.StakeCSMT.CSMT.Builder
    ( CredentialProof
    , buildCredentialProof
    , queryEpochRoot
    )
import Cardano.StakeCSMT.CSMT.Codecs
    ( EpochRoot (..)
    )
import Cardano.StakeCSMT.CSMT.Columns qualified as Stake
import Cardano.StakeCSMT.HTTP.API
    ( HistoryRootResponse (..)
    , LatestHeaderResponse
    , StakeProofResponse (..)
    , StakeRootResponse (..)
    , renderCredentialBase16
    , renderHashBase16
    , renderProofBase16
    )
import Cardano.StakeCSMT.HTTP.Signing
    ( signLatestHeader
    )
import Cardano.StakeCSMT.History.Builder qualified as HistoryBuilder
import Cardano.StakeCSMT.History.Columns qualified as HistoryCols
import Database.KV.Cursor
    ( Entry (..)
    , firstEntry
    , lastEntry
    , nextEntry
    )
import Database.KV.Transaction
    ( KV
    , Transaction
    , iterating
    )

queryHistoricalProof
    :: (Monad m)
    => EpochNo
    -> Credential Staking
    -> Transaction m cf Stake.Columns ops (Maybe StakeProofResponse)
queryHistoricalProof epoch credential = do
    mRoot <- queryEpochRoot epoch
    mProof <- buildCredentialProof epoch credential
    pure $ do
        root <- mRoot
        (stake, proof) <- mProof
        pure $ proofResponse epoch credential stake proof root

queryLatestProof
    :: (Monad m)
    => Credential Staking
    -> Transaction m cf Stake.Columns ops (Maybe StakeProofResponse)
queryLatestProof credential = do
    mLatest <- iterating Stake.RootCol lastEntry
    case mLatest of
        Nothing -> pure Nothing
        Just Entry{entryKey = epoch} ->
            queryHistoricalProof epoch credential

queryEpochRoots
    :: (Monad m)
    => Transaction m cf Stake.Columns ops [StakeRootResponse]
queryEpochRoots =
    iterating Stake.RootCol $ do
        mFirst <- firstEntry
        case mFirst of
            Nothing -> pure []
            Just first -> collect [rootResponse first]
  where
    collect roots = do
        mNext <- nextEntry
        case mNext of
            Nothing -> pure $ reverse roots
            Just entry -> collect $ rootResponse entry : roots

querySignedLatestHeader
    :: (Monad m)
    => SignKeyDSIGN Ed25519DSIGN
    -> Transaction m cf Stake.Columns ops (Maybe LatestHeaderResponse)
querySignedLatestHeader signingKey =
    fmap signedHeaderResponse <$> iterating Stake.RootCol lastEntry
  where
    signedHeaderResponse Entry{entryKey = epoch, entryValue = EpochRoot{..}} =
        signLatestHeader signingKey epoch epochRootHash epochRootTotalStake

queryCurrentHistoryRoot
    :: (Monad m)
    => Transaction m cf HistoryCols.Columns ops (Maybe HistoryRootResponse)
queryCurrentHistoryRoot =
    fmap (HistoryRootResponse . renderHashBase16)
        <$> HistoryBuilder.queryHistoryRoot

proofResponse
    :: EpochNo
    -> Credential Staking
    -> Coin
    -> CredentialProof
    -> EpochRoot
    -> StakeProofResponse
proofResponse epoch credential stake proof EpochRoot{..} =
    StakeProofResponse
        { epoch
        , credential = renderCredentialBase16 credential
        , stake
        , stakeRoot = renderHashBase16 epochRootHash
        , totalStake = epochRootTotalStake
        , proofBytes = renderProofBase16 $ renderProof proof
        }

rootResponse :: Entry (KV EpochNo EpochRoot) -> StakeRootResponse
rootResponse Entry{entryKey = epoch, entryValue = EpochRoot{..}} =
    StakeRootResponse
        { epoch
        , stakeRoot = renderHashBase16 epochRootHash
        , totalStake = epochRootTotalStake
        }
