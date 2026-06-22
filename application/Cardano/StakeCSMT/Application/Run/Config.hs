{- |
Module      : Cardano.StakeCSMT.Application.Run.Config
Description : Runtime configuration for the scaffold executable.

Only the HTTP port is configurable in the initial scaffold.
-}
module Cardano.StakeCSMT.Application.Run.Config
    ( RuntimeConfig (..)
    , configApiPort
    , defaultConfig
    ) where

data RuntimeConfig = RuntimeConfig
    { configPort :: Int
    , configDocsPort :: ~(Maybe Int)
    , configStakeDbPath :: ~(Maybe FilePath)
    , configHistoryDbPath :: ~(Maybe FilePath)
    }
    deriving stock (Eq, Show)

-- | Preferred API port accessor; 'configPort' is retained for compatibility.
configApiPort :: RuntimeConfig -> Int
configApiPort =
    configPort

defaultConfig :: RuntimeConfig
defaultConfig =
    RuntimeConfig
        { configPort = 8080
        , configDocsPort = Nothing
        , configStakeDbPath = Nothing
        , configHistoryDbPath = Nothing
        }
