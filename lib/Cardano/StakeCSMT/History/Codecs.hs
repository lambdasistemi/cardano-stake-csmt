{- |
Module      : Cardano.StakeCSMT.History.Codecs
Description : Stable codecs for history accumulator storage.

CBOR-backed codecs used by the history accumulator database schema.
-}
module Cardano.StakeCSMT.History.Codecs
    ( historyPrefix
    , historyRootKeyCodec
    , historyRootValueCodec
    , historyLeafHash
    )
where

import CSMT.Hashes
    ( Hash
    , byteStringToKey
    , mkHash
    )
import CSMT.Interface
    ( Key
    )
import Cardano.StakeCSMT.CSMT.Codecs
    ( EpochRoot
    , csmtHashCodec
    , epochRootCodec
    )
import Control.Lens
    ( Prism'
    , prism'
    , review
    )
import Data.ByteString
    ( ByteString
    )

-- | Deterministic namespace prefix for the epoch-root history tree.
historyPrefix :: Key
historyPrefix =
    byteStringToKey historyPrefixBytes

-- | Codec for the singleton current-history-root key.
historyRootKeyCodec :: Prism' ByteString ()
historyRootKeyCodec =
    prism' (const historyRootKeyBytes) decode
  where
    decode bytes
        | bytes == historyRootKeyBytes = Just ()
        | otherwise = Nothing

-- | Codec for the current history root hash.
historyRootValueCodec :: Prism' ByteString Hash
historyRootValueCodec =
    csmtHashCodec

-- | Hash an epoch root leaf, including both stake root and total stake.
historyLeafHash :: EpochRoot -> Hash
historyLeafHash =
    mkHash . review epochRootCodec

historyPrefixBytes :: ByteString
historyPrefixBytes =
    "cardano-stake-csmt-history-v1"

historyRootKeyBytes :: ByteString
historyRootKeyBytes =
    "current-root"
