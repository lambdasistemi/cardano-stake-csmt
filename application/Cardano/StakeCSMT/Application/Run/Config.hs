{- |
Module      : Cardano.StakeCSMT.Application.Run.Config
Description : Runtime configuration for the scaffold executable.

Only the HTTP port is configurable in the initial scaffold.
-}
module Cardano.StakeCSMT.Application.Run.Config
    ( RuntimeConfig (..)
    , apiPortEnvironmentVariable
    , configApiPort
    , defaultConfig
    , runtimeConfigFromEnvironment
    , runtimeConfigFromEnvironmentValues
    ) where

import Cardano.Crypto.DSIGN.Class
    ( SignKeyDSIGN
    )
import Cardano.Crypto.DSIGN.Ed25519
    ( Ed25519DSIGN
    )
import System.Environment
    ( lookupEnv
    )
import Text.Read
    ( readMaybe
    )

data RuntimeConfig = RuntimeConfig
    { configPort :: Int
    , configDocsPort :: ~(Maybe Int)
    , configStakeDbPath :: ~(Maybe FilePath)
    , configHistoryDbPath :: ~(Maybe FilePath)
    , configSigningKey :: ~(Maybe (SignKeyDSIGN Ed25519DSIGN))
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
        { configPort = 8080
        , configDocsPort = Nothing
        , configStakeDbPath = Nothing
        , configHistoryDbPath = Nothing
        , configSigningKey = Nothing
        }

runtimeConfigFromEnvironment :: IO RuntimeConfig
runtimeConfigFromEnvironment = do
    mApiPort <- lookupEnv apiPortEnvironmentVariable
    case runtimeConfigFromEnvironmentValues
        $ maybe
            []
            (\apiPort -> [(apiPortEnvironmentVariable, apiPort)])
            mApiPort of
        Left message -> fail message
        Right config -> pure config

runtimeConfigFromEnvironmentValues
    :: [(String, String)] -> Either String RuntimeConfig
runtimeConfigFromEnvironmentValues environment =
    case lookup apiPortEnvironmentVariable environment of
        Nothing ->
            Right defaultConfig
        Just rawApiPort -> do
            apiPort <- parseApiPort rawApiPort
            Right defaultConfig{configPort = apiPort}

parseApiPort :: String -> Either String Int
parseApiPort rawApiPort =
    case readMaybe rawApiPort of
        Just apiPort
            | apiPort >= 1 && apiPort <= 65535 ->
                Right apiPort
        _ ->
            Left
                $ apiPortEnvironmentVariable
                    <> " must be an integer between 1 and 65535"
