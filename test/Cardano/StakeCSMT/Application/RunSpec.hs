module Cardano.StakeCSMT.Application.RunSpec
    ( spec
    ) where

import Cardano.Crypto.DSIGN.Class
    ( SignKeyDSIGN
    , genKeyDSIGN
    , rawSerialiseSignKeyDSIGN
    )
import Cardano.Crypto.DSIGN.Ed25519
    ( Ed25519DSIGN
    )
import Cardano.Crypto.Seed
    ( mkSeedFromBytes
    )
import Cardano.StakeCSMT.Application.Run.CLI
    ( runtimeConfigFromArguments
    )
import Cardano.StakeCSMT.Application.Run.Config
    ( RuntimeConfig (..)
    , apiPortEnvironmentVariable
    , configApiPort
    , defaultConfig
    )
import Cardano.StakeCSMT.Application.Run.Main
    ( RuntimeApplications (..)
    , applications
    , markRuntimeReady
    , newRuntimeReadinessSignal
    , withRuntimeHandlersUsingReadiness
    )
import Cardano.StakeCSMT.HTTP.API
    ( ReadyResponse (..)
    )
import Cardano.StakeCSMT.HTTP.Server
    ( QueryHandlers (queryReady)
    , unavailableHandlers
    )
import Data.ByteString
    ( ByteString
    )
import Data.ByteString qualified as BS
import Data.List
    ( isInfixOf
    )
import Network.HTTP.Types
    ( methodGet
    , status200
    )
import Network.Wai
    ( Application
    , requestMethod
    )
import Network.Wai.Test
    ( SResponse
    , runSession
    )
import Network.Wai.Test qualified as WaiTest
import System.Directory
    ( createDirectory
    )
import System.FilePath
    ( (</>)
    )
import System.IO.Temp
    ( withSystemTempDirectory
    )
import Test.Hspec
    ( Expectation
    , Spec
    , describe
    , expectationFailure
    , it
    , shouldBe
    , shouldSatisfy
    )

spec :: Spec
spec =
    describe "Application.Run" $ do
        describe "runtime CLI config" $ do
            it "parses all required CLI flags"
                $ withRuntimeFixture
                $ \fixture -> do
                    result <- runtimeConfigFromArguments (requiredArgs fixture) []
                    result `shouldBe` Right (expectedConfig fixture)

            mapM_
                ( \(label, flag, fallback) ->
                    it ("rejects a missing " <> label)
                        $ withRuntimeFixture
                        $ \fixture -> do
                            result <-
                                runtimeConfigFromArguments
                                    (removeFlag flag $ requiredArgs fixture)
                                    []
                            result `shouldFailWith` flag
                            result `shouldFailWith` fallback
                )
                requiredInputs

            it "rejects an invalid node socket path"
                $ withRuntimeFixture
                $ \fixture -> do
                    let missingSocket = fixtureRoot fixture </> "missing.socket"
                    result <-
                        runtimeConfigFromArguments
                            ( setFlag
                                "--node-socket"
                                missingSocket
                                $ requiredArgs fixture
                            )
                            []
                    result `shouldFailWith` missingSocket

            it "rejects an invalid ledger config directory"
                $ withRuntimeFixture
                $ \fixture -> do
                    let missingLedgerDir = fixtureRoot fixture </> "missing-ledger"
                    result <-
                        runtimeConfigFromArguments
                            ( setFlag
                                "--ledger-config-dir"
                                missingLedgerDir
                                $ requiredArgs fixture
                            )
                            []
                    result `shouldFailWith` missingLedgerDir

            it "rejects invalid network magic"
                $ withRuntimeFixture
                $ \fixture -> do
                    result <-
                        runtimeConfigFromArguments
                            ( setFlag
                                "--network-magic"
                                "not-a-number"
                                $ requiredArgs fixture
                            )
                            []
                    result `shouldFailWith` "--network-magic"

            it "rejects invalid Byron epoch slots"
                $ withRuntimeFixture
                $ \fixture -> do
                    result <-
                        runtimeConfigFromArguments
                            (requiredArgs fixture <> ["--byron-epoch-slots", "0"])
                            []
                    result `shouldFailWith` "--byron-epoch-slots"

            mapM_
                ( \(flag, rawPort) ->
                    it ("rejects invalid " <> flag <> " " <> rawPort)
                        $ withRuntimeFixture
                        $ \fixture -> do
                            result <-
                                runtimeConfigFromArguments
                                    (requiredArgs fixture <> [flag, rawPort])
                                    []
                            result `shouldFailWith` flag
                )
                [ ("--api-port", "0")
                , ("--api-port", "65536")
                , ("--api-port", "not-a-number")
                , ("--docs-port", "0")
                , ("--docs-port", "65536")
                , ("--docs-port", "not-a-number")
                ]

            it "uses the existing API port environment fallback"
                $ withRuntimeFixture
                $ \fixture -> do
                    result <-
                        runtimeConfigFromArguments
                            (requiredArgs fixture)
                            [(apiPortEnvironmentVariable, "18080")]
                    (configPort <$> result) `shouldBe` Right 18080

            it "uses the database path environment fallback"
                $ withRuntimeFixture
                $ \fixture -> do
                    result <-
                        runtimeConfigFromArguments
                            (removeFlag "--db" $ requiredArgs fixture)
                            [
                                ( "CARDANO_STAKE_CSMT_DB"
                                , fixtureDbPath fixture
                                )
                            ]
                    (configDbPath <$> result)
                        `shouldBe` Right (fixtureDbPath fixture)

            it "loads an Ed25519 signing key from a file"
                $ withRuntimeFixture
                $ \fixture -> do
                    let keyPath = fixtureRoot fixture </> "signing.key"
                    BS.writeFile keyPath $ rawSerialiseSignKeyDSIGN signingKey
                    result <-
                        runtimeConfigFromArguments
                            (requiredArgs fixture <> ["--signing-key", keyPath])
                            []
                    case result of
                        Left message ->
                            expectationFailure message
                        Right config -> do
                            configSigningKeyPath config `shouldBe` Just keyPath
                            configSigningKey config `shouldBe` Just signingKey

        it "keeps default HTTP-facing runtime config values" $ do
            configApiPort defaultConfig `shouldBe` 8080
            configDocsPort defaultConfig `shouldBe` Nothing
            configCheckpointDir defaultConfig `shouldBe` Nothing
            configSigningKeyPath defaultConfig `shouldBe` Nothing

        it "composes API and optional docs applications" $ do
            let config = defaultConfig{configDocsPort = Just 8081}
                RuntimeApplications{runtimeApiApp, runtimeDocsApp} =
                    applications config unavailableHandlers

            apiResponse <- get "/ready" runtimeApiApp
            WaiTest.simpleStatus apiResponse `shouldBe` status200

            case runtimeDocsApp of
                Nothing -> fail "expected docs application"
                Just docs -> do
                    docsResponse <- get "/swagger.json" docs
                    WaiTest.simpleStatus docsResponse `shouldBe` status200

        it "threads runtime readiness through a shared signal"
            $ withRuntimeFixture
            $ \fixture -> do
                readiness <- newRuntimeReadinessSignal
                withRuntimeHandlersUsingReadiness
                    readiness
                    (expectedConfig fixture)
                    $ \handlers -> do
                        queryReady handlers
                            >>= (`shouldBe` ReadyResponse{ready = False})
                        markRuntimeReady readiness
                        queryReady handlers
                            >>= (`shouldBe` ReadyResponse{ready = True})

data RuntimeFixture = RuntimeFixture
    { fixtureRoot :: FilePath
    , fixtureNodeSocket :: FilePath
    , fixtureLedgerConfigDir :: FilePath
    , fixtureDbPath :: FilePath
    }

withRuntimeFixture :: (RuntimeFixture -> IO a) -> IO a
withRuntimeFixture action =
    withSystemTempDirectory "stake-csmt-runtime" $ \root -> do
        let nodeSocket = root </> "node.socket"
            ledgerConfigDir = root </> "ledger-config"
            fixture =
                RuntimeFixture
                    { fixtureRoot = root
                    , fixtureNodeSocket = nodeSocket
                    , fixtureLedgerConfigDir = ledgerConfigDir
                    , fixtureDbPath = root </> "store.db"
                    }
        BS.writeFile nodeSocket ""
        createDirectory ledgerConfigDir
        action fixture

requiredArgs :: RuntimeFixture -> [String]
requiredArgs fixture =
    [ "--node-socket"
    , fixtureNodeSocket fixture
    , "--network-magic"
    , "42"
    , "--ledger-config-dir"
    , fixtureLedgerConfigDir fixture
    , "--db"
    , fixtureDbPath fixture
    ]

expectedConfig :: RuntimeFixture -> RuntimeConfig
expectedConfig fixture =
    RuntimeConfig
        { configNodeSocketPath = fixtureNodeSocket fixture
        , configNetworkMagic = 42
        , configByronEpochSlots = 21_600
        , configLedgerConfigDir = fixtureLedgerConfigDir fixture
        , configDbPath = fixtureDbPath fixture
        , configCheckpointDir = Nothing
        , configSigningKeyPath = Nothing
        , configSigningKey = Nothing
        , configPort = 8080
        , configDocsPort = Nothing
        }

requiredInputs :: [(String, String, String)]
requiredInputs =
    [
        ( "node socket"
        , "--node-socket"
        , "CARDANO_STAKE_CSMT_NODE_SOCKET"
        )
    ,
        ( "network magic"
        , "--network-magic"
        , "CARDANO_STAKE_CSMT_NETWORK_MAGIC"
        )
    ,
        ( "ledger config directory"
        , "--ledger-config-dir"
        , "CARDANO_STAKE_CSMT_LEDGER_CONFIG_DIR"
        )
    ,
        ( "database path"
        , "--db"
        , "CARDANO_STAKE_CSMT_DB"
        )
    ]

removeFlag :: String -> [String] -> [String]
removeFlag _ [] = []
removeFlag flag (candidate : value : rest)
    | candidate == flag = rest
    | otherwise = candidate : value : removeFlag flag rest
removeFlag _ singleton =
    singleton

setFlag :: String -> String -> [String] -> [String]
setFlag flag newValue = go
  where
    go [] = []
    go (candidate : _oldValue : rest)
        | candidate == flag = candidate : newValue : rest
    go (candidate : value : rest) =
        candidate : value : go rest
    go singleton =
        singleton

shouldFailWith :: Show a => Either String a -> String -> Expectation
shouldFailWith result expectedMessage =
    case result of
        Left message ->
            message `shouldSatisfy` (expectedMessage `isInfixOf`)
        Right value ->
            expectationFailure $ "expected failure but parsed " <> show value

signingKey :: SignKeyDSIGN Ed25519DSIGN
signingKey =
    genKeyDSIGN @Ed25519DSIGN $ mkSeedFromBytes $ BS.replicate 32 11

get :: ByteString -> Application -> IO SResponse
get path =
    runSession
        ( WaiTest.request
            $ WaiTest.setPath
                WaiTest.defaultRequest{requestMethod = methodGet}
                path
        )
