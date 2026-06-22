{- |
Module      : Cardano.StakeCSMT.HTTP.Signing
Description : Ed25519 signatures for latest stake root headers.

Signs deterministic binary latest-header payloads for HTTP responses.
-}
module Cardano.StakeCSMT.HTTP.Signing
    ( latestHeaderPayload
    , signLatestHeader
    , verifyLatestHeader
    , verifyLatestHeaderWith
    ) where

import CSMT.Hashes
    ( Hash
    , renderHash
    )
import Cardano.Crypto.DSIGN.Class
    ( SigDSIGN
    , SignKeyDSIGN
    , VerKeyDSIGN
    , deriveVerKeyDSIGN
    , rawDeserialiseSigDSIGN
    , rawDeserialiseVerKeyDSIGN
    , rawSerialiseSigDSIGN
    , rawSerialiseVerKeyDSIGN
    , signDSIGN
    , verifyDSIGN
    )
import Cardano.Crypto.DSIGN.Ed25519
    ( Ed25519DSIGN
    )
import Cardano.Ledger.Coin
    ( Coin
    )
import Cardano.Slotting.Slot
    ( EpochNo
    )
import Cardano.StakeCSMT.CSMT.Codecs
    ( coinCodec
    , epochNoCodec
    )
import Cardano.StakeCSMT.HTTP.API
    ( LatestHeaderResponse (..)
    , parseHashBase16
    , renderHashBase16
    )
import Cardano.StakeCSMT.HTTP.Base16
    ( decodeBase16Text
    , encodeBase16Text
    )
import Control.Lens
    ( review
    )
import Data.ByteString
    ( ByteString
    )
import Data.Either
    ( isRight
    )
import Data.Text
    ( Text
    )

-- | Deterministic binary payload signed by latest-header responses.
latestHeaderPayload :: EpochNo -> Hash -> Coin -> ByteString
latestHeaderPayload epoch root totalStake =
    review epochNoCodec epoch
        <> renderHash root
        <> review coinCodec totalStake

-- | Sign the latest persisted root as an HTTP response.
signLatestHeader
    :: SignKeyDSIGN Ed25519DSIGN
    -> EpochNo
    -> Hash
    -> Coin
    -> LatestHeaderResponse
signLatestHeader signingKey epoch root totalStake =
    LatestHeaderResponse
        { epoch
        , stakeRoot = renderHashBase16 root
        , totalStake
        , signature = encodeBase16Text $ rawSerialiseSigDSIGN sig
        , publicKey = encodeBase16Text $ rawSerialiseVerKeyDSIGN verKey
        }
  where
    verKey =
        deriveVerKeyDSIGN signingKey
    sig =
        signDSIGN () (latestHeaderPayload epoch root totalStake) signingKey

-- | Verify a latest-header response using its embedded public key.
verifyLatestHeader :: LatestHeaderResponse -> Bool
verifyLatestHeader header@LatestHeaderResponse{publicKey} =
    case parseVerKeyBase16 publicKey of
        Nothing -> False
        Just verKey -> verifyLatestHeaderWith verKey header

-- | Verify a latest-header response using an expected public key.
verifyLatestHeaderWith
    :: VerKeyDSIGN Ed25519DSIGN
    -> LatestHeaderResponse
    -> Bool
verifyLatestHeaderWith
    verKey
    LatestHeaderResponse{epoch, stakeRoot, totalStake, signature} =
        case (parseHashBase16 stakeRoot, parseSigBase16 signature) of
            (Right root, Just sig) ->
                isRight
                    $ verifyDSIGN
                        ()
                        verKey
                        (latestHeaderPayload epoch root totalStake)
                        sig
            _ -> False

parseVerKeyBase16 :: Text -> Maybe (VerKeyDSIGN Ed25519DSIGN)
parseVerKeyBase16 text =
    either (const Nothing) (rawDeserialiseVerKeyDSIGN @Ed25519DSIGN)
        $ decodeBase16Text text

parseSigBase16 :: Text -> Maybe (SigDSIGN Ed25519DSIGN)
parseSigBase16 text =
    either (const Nothing) (rawDeserialiseSigDSIGN @Ed25519DSIGN)
        $ decodeBase16Text text
