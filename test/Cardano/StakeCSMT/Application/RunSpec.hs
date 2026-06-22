module Cardano.StakeCSMT.Application.RunSpec
    ( spec
    ) where

import Cardano.StakeCSMT.Application.Run.Config
    ( RuntimeConfig (..)
    , apiPortEnvironmentVariable
    , configApiPort
    , defaultConfig
    , runtimeConfigFromEnvironmentValues
    )
import Cardano.StakeCSMT.Application.Run.Main
    ( RuntimeApplications (..)
    , applications
    , withRuntimeHandlers
    )
import Cardano.StakeCSMT.HTTP.Server
    ( apiApp
    )
import Data.ByteString
    ( ByteString
    )
import Data.Either
    ( isLeft
    )
import Network.HTTP.Types
    ( methodGet
    , status200
    , status503
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
import Test.Hspec
    ( Spec
    , describe
    , it
    , shouldBe
    , shouldSatisfy
    )

spec :: Spec
spec =
    describe "Application.Run" $ do
        it "keeps default runtime config runnable without databases" $ do
            configApiPort defaultConfig `shouldBe` 8080
            configDocsPort defaultConfig `shouldBe` Nothing
            configStakeDbPath defaultConfig `shouldBe` Nothing
            configHistoryDbPath defaultConfig `shouldBe` Nothing

        it "keeps the default API port when the environment is absent"
            $ runtimeConfigFromEnvironmentValues []
            `shouldBe` Right defaultConfig

        it "overrides the API port from the environment"
            $ runtimeConfigFromEnvironmentValues
                [(apiPortEnvironmentVariable, "18080")]
            `shouldBe` Right defaultConfig{configPort = 18080}

        it "rejects invalid API port environment values"
            $ mapM_
                ( \rawApiPort ->
                    runtimeConfigFromEnvironmentValues
                        [(apiPortEnvironmentVariable, rawApiPort)]
                        `shouldSatisfy` isLeft
                )
                ["", "abc", "0", "65536", "-1"]

        it "uses the unavailable query backend when DB paths are absent"
            $ withRuntimeHandlers defaultConfig
            $ \handlers -> do
                response <- get "/roots" $ apiApp handlers
                WaiTest.simpleStatus response `shouldBe` status503

        it "composes API and optional docs applications"
            $ withRuntimeHandlers defaultConfig
            $ \handlers -> do
                let config = defaultConfig{configDocsPort = Just 8081}
                    RuntimeApplications{runtimeApiApp, runtimeDocsApp} =
                        applications config handlers

                apiResponse <- get "/ready" runtimeApiApp
                WaiTest.simpleStatus apiResponse `shouldBe` status200

                case runtimeDocsApp of
                    Nothing -> fail "expected docs application"
                    Just docs -> do
                        docsResponse <- get "/swagger.json" docs
                        WaiTest.simpleStatus docsResponse `shouldBe` status200

get :: ByteString -> Application -> IO SResponse
get path =
    runSession
        ( WaiTest.request
            $ WaiTest.setPath
                WaiTest.defaultRequest{requestMethod = methodGet}
                path
        )
