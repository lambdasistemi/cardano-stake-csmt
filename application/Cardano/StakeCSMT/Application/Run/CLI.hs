{- |
Module      : Cardano.StakeCSMT.Application.Run.CLI
Description : Command-line runtime configuration parser.
-}
module Cardano.StakeCSMT.Application.Run.CLI
    ( runtimeConfigFromArguments
    , runtimeConfigFromCommandLine
    ) where

import Cardano.Crypto.DSIGN.Class
    ( SignKeyDSIGN
    , rawDeserialiseSignKeyDSIGN
    )
import Cardano.Crypto.DSIGN.Ed25519
    ( Ed25519DSIGN
    )
import Cardano.StakeCSMT.Application.Run.Config
    ( RuntimeConfig (..)
    , apiPortEnvironmentVariable
    )
import Control.Applicative
    ( (<|>)
    )
import Control.Exception
    ( IOException
    , try
    )
import Data.ByteString qualified as BS
import Data.List
    ( isPrefixOf
    )
import Data.Word
    ( Word32
    , Word64
    )
import System.Directory
    ( doesDirectoryExist
    , doesFileExist
    )
import System.Environment
    ( getArgs
    , getEnvironment
    )
import Text.Read
    ( readMaybe
    )

runtimeConfigFromCommandLine :: IO RuntimeConfig
runtimeConfigFromCommandLine = do
    arguments <- getArgs
    environment <- getEnvironment
    runtimeConfigFromArguments arguments environment >>= \case
        Left message -> fail message
        Right config -> pure config

runtimeConfigFromArguments
    :: [String] -> [(String, String)] -> IO (Either String RuntimeConfig)
runtimeConfigFromArguments arguments environment =
    case parseArguments arguments >>= parseRuntimeValues environment of
        Left message ->
            pure $ Left message
        Right values ->
            validateRuntimeValues values

data RuntimeValues = RuntimeValues
    { valuesNodeSocketPath :: FilePath
    , valuesNetworkMagic :: Word32
    , valuesByronEpochSlots :: Word64
    , valuesLedgerConfigDir :: FilePath
    , valuesDbPath :: FilePath
    , valuesCheckpointDir :: Maybe FilePath
    , valuesSigningKeyPath :: Maybe FilePath
    , valuesPort :: Int
    , valuesDocsPort :: Maybe Int
    }

data Option = Option
    { optionFlag :: String
    , optionEnvironmentVariable :: String
    }

nodeSocketOption :: Option
nodeSocketOption =
    Option
        "--node-socket"
        "CARDANO_STAKE_CSMT_NODE_SOCKET"

networkMagicOption :: Option
networkMagicOption =
    Option
        "--network-magic"
        "CARDANO_STAKE_CSMT_NETWORK_MAGIC"

byronEpochSlotsOption :: Option
byronEpochSlotsOption =
    Option
        "--byron-epoch-slots"
        "CARDANO_STAKE_CSMT_BYRON_EPOCH_SLOTS"

ledgerConfigDirOption :: Option
ledgerConfigDirOption =
    Option
        "--ledger-config-dir"
        "CARDANO_STAKE_CSMT_LEDGER_CONFIG_DIR"

dbOption :: Option
dbOption =
    Option
        "--db"
        "CARDANO_STAKE_CSMT_DB"

checkpointDirOption :: Option
checkpointDirOption =
    Option
        "--checkpoint-dir"
        "CARDANO_STAKE_CSMT_CHECKPOINT_DIR"

signingKeyOption :: Option
signingKeyOption =
    Option
        "--signing-key"
        "CARDANO_STAKE_CSMT_SIGNING_KEY"

apiPortOption :: Option
apiPortOption =
    Option "--api-port" apiPortEnvironmentVariable

docsPortOption :: Option
docsPortOption =
    Option
        "--docs-port"
        "CARDANO_STAKE_CSMT_DOCS_PORT"

supportedOptions :: [Option]
supportedOptions =
    [ nodeSocketOption
    , networkMagicOption
    , byronEpochSlotsOption
    , ledgerConfigDirOption
    , dbOption
    , checkpointDirOption
    , signingKeyOption
    , apiPortOption
    , docsPortOption
    ]

parseArguments :: [String] -> Either String [(String, String)]
parseArguments [] =
    Right []
parseArguments [flag]
    | isSupportedFlag flag =
        Left $ flag <> " requires a value"
    | "--" `isPrefixOf` flag =
        Left $ "unknown flag " <> flag
    | otherwise =
        Left $ "unexpected argument " <> flag
parseArguments (flag : value : rest)
    | isSupportedFlag flag =
        if isSupportedFlag value
            then Left $ flag <> " requires a value"
            else ((flag, value) :) <$> parseArguments rest
    | "--" `isPrefixOf` flag =
        Left $ "unknown flag " <> flag
    | otherwise =
        Left $ "unexpected argument " <> flag

isSupportedFlag :: String -> Bool
isSupportedFlag flag =
    flag `elem` fmap optionFlag supportedOptions

parseRuntimeValues
    :: [(String, String)]
    -> [(String, String)]
    -> Either String RuntimeValues
parseRuntimeValues environment options = do
    nodeSocketPath <- requiredPath nodeSocketOption
    networkMagic <-
        requiredValue networkMagicOption
            >>= parseWord32 networkMagicOption
    byronEpochSlots <-
        optionalValue byronEpochSlotsOption
            >>= maybe
                (Right 21_600)
                (parsePositiveWord64 byronEpochSlotsOption)
    ledgerConfigDir <- requiredPath ledgerConfigDirOption
    dbPath <- requiredPath dbOption
    checkpointDir <- optionalPath checkpointDirOption
    signingKeyPath <- optionalPath signingKeyOption
    port <-
        optionalValue apiPortOption
            >>= maybe
                (Right 8080)
                (parsePort apiPortOption)
    docsPort <-
        optionalValue docsPortOption
            >>= traverse (parsePort docsPortOption)
    Right
        RuntimeValues
            { valuesNodeSocketPath = nodeSocketPath
            , valuesNetworkMagic = networkMagic
            , valuesByronEpochSlots = byronEpochSlots
            , valuesLedgerConfigDir = ledgerConfigDir
            , valuesDbPath = dbPath
            , valuesCheckpointDir = checkpointDir
            , valuesSigningKeyPath = signingKeyPath
            , valuesPort = port
            , valuesDocsPort = docsPort
            }
  where
    requiredPath option =
        requiredValue option >>= nonEmptyValue (optionFlag option)

    optionalPath option =
        optionalValue option >>= traverse (nonEmptyValue $ optionFlag option)

    requiredValue option =
        case lookupValue option options environment of
            Nothing ->
                Left
                    $ "missing required "
                        <> optionFlag option
                        <> " (or "
                        <> optionEnvironmentVariable option
                        <> ")"
            Just value ->
                Right value

    optionalValue option =
        Right $ lookupValue option options environment

lookupValue
    :: Option -> [(String, String)] -> [(String, String)] -> Maybe String
lookupValue Option{optionFlag, optionEnvironmentVariable} options environment =
    lookup optionFlag options
        <|> lookup optionEnvironmentVariable environment

validateRuntimeValues
    :: RuntimeValues -> IO (Either String RuntimeConfig)
validateRuntimeValues values = do
    nodeSocketExists <- doesFileExist $ valuesNodeSocketPath values
    ledgerConfigDirExists <-
        doesDirectoryExist $ valuesLedgerConfigDir values
    signingKey <- loadSigningKey $ valuesSigningKeyPath values
    pure $ do
        if nodeSocketExists
            then Right ()
            else
                Left
                    $ "--node-socket path does not exist: "
                        <> valuesNodeSocketPath values
        if ledgerConfigDirExists
            then Right ()
            else
                Left
                    $ "--ledger-config-dir directory does not exist: "
                        <> valuesLedgerConfigDir values
        loadedSigningKey <- signingKey
        Right
            RuntimeConfig
                { configNodeSocketPath = valuesNodeSocketPath values
                , configNetworkMagic = valuesNetworkMagic values
                , configByronEpochSlots = valuesByronEpochSlots values
                , configLedgerConfigDir = valuesLedgerConfigDir values
                , configDbPath = valuesDbPath values
                , configCheckpointDir = valuesCheckpointDir values
                , configSigningKeyPath = valuesSigningKeyPath values
                , configSigningKey = loadedSigningKey
                , configPort = valuesPort values
                , configDocsPort = valuesDocsPort values
                }

loadSigningKey
    :: Maybe FilePath
    -> IO (Either String (Maybe (SignKeyDSIGN Ed25519DSIGN)))
loadSigningKey Nothing =
    pure $ Right Nothing
loadSigningKey (Just path) = do
    rawOrError <- try $ BS.readFile path
    case rawOrError of
        Left (exception :: IOException) ->
            pure
                $ Left
                $ "--signing-key could not read "
                    <> path
                    <> ": "
                    <> show exception
        Right raw ->
            pure
                $ case rawDeserialiseSignKeyDSIGN @Ed25519DSIGN raw of
                    Nothing ->
                        Left
                            $ "--signing-key could not decode Ed25519 signing key from "
                                <> path
                    Just signingKey ->
                        Right $ Just signingKey

parseWord32 :: Option -> String -> Either String Word32
parseWord32 option raw =
    case readMaybe @Integer raw of
        Just value
            | value >= 0 && value <= fromIntegral (maxBound :: Word32) ->
                Right $ fromIntegral value
        _ ->
            Left
                $ optionFlag option
                    <> " must be an integer between 0 and "
                    <> show (maxBound :: Word32)

parsePositiveWord64 :: Option -> String -> Either String Word64
parsePositiveWord64 option raw =
    case readMaybe @Integer raw of
        Just value
            | value > 0 && value <= fromIntegral (maxBound :: Word64) ->
                Right $ fromIntegral value
        _ ->
            Left
                $ optionFlag option
                    <> " must be a positive integer"

parsePort :: Option -> String -> Either String Int
parsePort option raw =
    case readMaybe @Integer raw of
        Just value
            | value >= 1 && value <= 65_535 ->
                Right $ fromIntegral value
        _ ->
            Left
                $ optionFlag option
                    <> " must be an integer between 1 and 65535"

nonEmptyValue :: String -> String -> Either String String
nonEmptyValue label value
    | null value = Left $ label <> " must not be empty"
    | otherwise = Right value
