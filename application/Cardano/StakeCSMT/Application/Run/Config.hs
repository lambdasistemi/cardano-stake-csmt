{- |
Module      : Cardano.StakeCSMT.Application.Run.Config
Description : Runtime configuration for the daemon executable.
-}
module Cardano.StakeCSMT.Application.Run.Config
    ( RuntimeConfig (..)
    , apiPortEnvironmentVariable
    , configApiPort
    , defaultConfig
    ) where

import Cardano.Crypto.DSIGN.Class
    ( SignKeyDSIGN
    )
import Cardano.Crypto.DSIGN.Ed25519
    ( Ed25519DSIGN
    )
import Data.Word
    ( Word32
    , Word64
    )

data RuntimeConfig = RuntimeConfig
    { configNodeSocketPath :: FilePath
    , configNetworkMagic :: Word32
    , configByronEpochSlots :: Word64
    , configLedgerConfigDir :: FilePath
    , configStakeDbPath :: FilePath
    , configHistoryDbPath :: FilePath
    , configCheckpointDir :: Maybe FilePath
    , configSigningKeyPath :: Maybe FilePath
    , configSigningKey :: Maybe (SignKeyDSIGN Ed25519DSIGN)
    , configPort :: Int
    , configDocsPort :: ~(Maybe Int)
    }
    deriving stock (Eq, Show)

-- | Preferred API port accessor; 'configPort' is retained for compatibility.
configApiPort :: RuntimeConfig -> Int
configApiPort =
    configPort

apiPortEnvironmentVariable :: String
apiPortEnvironmentVariable =
    "CARDANO_STAKE_CSMT_API_PORT"

defaultConfig :: RuntimeConfig
defaultConfig =
    RuntimeConfig
        { configNodeSocketPath = "/dev/null"
        , configNetworkMagic = 0
        , configByronEpochSlots = 21_600
        , configLedgerConfigDir = "."
        , configStakeDbPath = "stake.db"
        , configHistoryDbPath = "history.db"
        , configCheckpointDir = Nothing
        , configSigningKeyPath = Nothing
        , configSigningKey = Nothing
        , configPort = 8080
        , configDocsPort = Nothing
        }
