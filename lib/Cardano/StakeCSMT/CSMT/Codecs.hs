{- |
Module      : Cardano.StakeCSMT.CSMT.Codecs
Description : Stable codecs for stake CSMT storage.

CBOR and ledger-CBOR codecs used by the stake CSMT database schema.
-}
module Cardano.StakeCSMT.CSMT.Codecs
    ( Direction (..)
    , EpochRoot (..)
    , Hash
    , Indirect (..)
    , Key
    , coinCodec
    , credentialCodec
    , csmtHashCodec
    , csmtIndirectHashCodec
    , csmtKeyCodec
    , epochNoCodec
    , epochPrefix
    , epochRootCodec
    , snapshotKeyCodec
    )
where

import CSMT.Hashes
    ( Hash
    , byteStringToKey
    , parseHash
    , renderHash
    )
import CSMT.Interface
    ( Direction (..)
    , Indirect (..)
    , Key
    )
import Cardano.Ledger.Binary
    ( DecCBOR
    , EncCBOR
    , decodeFull'
    , natVersion
    , serialize'
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
import Codec.CBOR.Decoding qualified as CBOR
import Codec.CBOR.Encoding qualified as CBOR
import Codec.CBOR.Read qualified as CBOR
import Codec.CBOR.Write qualified as CBOR
import Control.Lens
    ( Prism'
    , preview
    , prism'
    , review
    )
import Control.Monad
    ( replicateM
    , unless
    )
import Data.ByteString
    ( ByteString
    )
import Data.ByteString.Lazy qualified as BL

-- | Stored root metadata for a completed epoch stake tree.
data EpochRoot = EpochRoot
    { epochRootHash :: !Hash
    , epochRootTotalStake :: !Coin
    }
    deriving stock (Eq, Show)

-- | Ledger-CBOR codec for stake amounts.
coinCodec :: Prism' ByteString Coin
coinCodec = ledgerCodec

-- | Ledger-CBOR codec for staking credentials.
credentialCodec :: Prism' ByteString (Credential Staking)
credentialCodec = ledgerCodec

-- | Ledger-CBOR codec for epoch numbers.
epochNoCodec :: Prism' ByteString EpochNo
epochNoCodec = ledgerCodec

-- | Stable CSMT hash codec.
csmtHashCodec :: Prism' ByteString Hash
csmtHashCodec = prism' renderHash parseHash

-- | CBOR codec for CSMT tree keys.
csmtKeyCodec :: Prism' ByteString Key
csmtKeyCodec = prism' (encodeCBOR . encodeKey) (decodeCBOR decodeKey)

-- | CBOR codec for CSMT indirect hash nodes.
csmtIndirectHashCodec :: Prism' ByteString (Indirect Hash)
csmtIndirectHashCodec =
    prism' encode decode
  where
    encode Indirect{jump, value} =
        encodeCBOR
            $ CBOR.encodeListLen 2
                <> encodeKey jump
                <> CBOR.encodeBytes (review csmtHashCodec value)

    decode bs = do
        (jump, hashBytes) <-
            decodeCBOR
                ( do
                    decodeListLenOf 2
                    decodedJump <- decodeKey
                    decodedHash <- CBOR.decodeBytes
                    pure (decodedJump, decodedHash)
                )
                bs
        value <- preview csmtHashCodec hashBytes
        pure Indirect{jump, value}

-- | CBOR codec for epoch root records.
epochRootCodec :: Prism' ByteString EpochRoot
epochRootCodec =
    prism' encode decode
  where
    encode EpochRoot{epochRootHash, epochRootTotalStake} =
        encodeCBOR
            $ CBOR.encodeListLen 2
                <> CBOR.encodeBytes (review csmtHashCodec epochRootHash)
                <> CBOR.encodeBytes (review coinCodec epochRootTotalStake)

    decode bs = do
        (hashBytes, stakeBytes) <-
            decodeCBOR
                ( do
                    decodeListLenOf 2
                    decodedHash <- CBOR.decodeBytes
                    decodedStake <- CBOR.decodeBytes
                    pure (decodedHash, decodedStake)
                )
                bs
        epochRootHash <- preview csmtHashCodec hashBytes
        epochRootTotalStake <- preview coinCodec stakeBytes
        pure EpochRoot{epochRootHash, epochRootTotalStake}

-- | Codec for the stake snapshot column key.
snapshotKeyCodec :: Prism' ByteString (EpochNo, Credential Staking)
snapshotKeyCodec =
    prism' encode decode
  where
    encode (epoch, credential) =
        encodeCBOR
            $ CBOR.encodeListLen 2
                <> CBOR.encodeBytes (review epochNoCodec epoch)
                <> CBOR.encodeBytes (review credentialCodec credential)

    decode bs = do
        (epochBytes, credentialBytes) <-
            decodeCBOR
                ( do
                    decodeListLenOf 2
                    decodedEpoch <- CBOR.decodeBytes
                    decodedCredential <- CBOR.decodeBytes
                    pure (decodedEpoch, decodedCredential)
                )
                bs
        epoch <- preview epochNoCodec epochBytes
        credential <- preview credentialCodec credentialBytes
        pure (epoch, credential)

-- | Deterministic namespace prefix for one epoch tree.
epochPrefix :: EpochNo -> Key
epochPrefix = byteStringToKey . review epochNoCodec

ledgerCodec :: (EncCBOR a, DecCBOR a) => Prism' ByteString a
ledgerCodec =
    prism'
        (serialize' $ natVersion @11)
        (either (const Nothing) Just . decodeFull' (natVersion @11))

encodeCBOR :: CBOR.Encoding -> ByteString
encodeCBOR = BL.toStrict . CBOR.toLazyByteString

decodeCBOR
    :: (forall s. CBOR.Decoder s a)
    -> ByteString
    -> Maybe a
decodeCBOR decoder bs =
    case CBOR.deserialiseFromBytes decoder (BL.fromStrict bs) of
        Right (rest, value)
            | BL.null rest -> Just value
        _ -> Nothing

encodeDirection :: Direction -> CBOR.Encoding
encodeDirection L = CBOR.encodeWord 0
encodeDirection R = CBOR.encodeWord 1

decodeDirection :: CBOR.Decoder s Direction
decodeDirection = do
    word <- CBOR.decodeWord
    case word of
        0 -> pure L
        1 -> pure R
        _ -> fail "invalid CSMT direction"

encodeKey :: Key -> CBOR.Encoding
encodeKey directions =
    CBOR.encodeListLen (fromIntegral $ length directions)
        <> foldMap encodeDirection directions

decodeKey :: CBOR.Decoder s Key
decodeKey = do
    len <- CBOR.decodeListLen
    replicateM len decodeDirection

decodeListLenOf :: Int -> CBOR.Decoder s ()
decodeListLenOf expected = do
    actual <- CBOR.decodeListLen
    unless (actual == expected)
        $ fail "unexpected CBOR list length"
