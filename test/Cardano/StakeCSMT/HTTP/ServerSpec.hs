module Cardano.StakeCSMT.HTTP.ServerSpec
    ( spec
    ) where

import Cardano.StakeCSMT.HTTP.Server
    ( responseForPath
    )
import Network.HTTP.Types
    ( status200
    , status404
    )
import Test.Hspec
    ( Spec
    , describe
    , it
    , shouldBe
    )

spec :: Spec
spec = do
    describe "responseForPath" $ do
        it "serves /health"
            $ responseForPath ["health"]
            `shouldBe` (status200, "ok\n")

        it "serves /ready"
            $ responseForPath ["ready"]
            `shouldBe` (status200, "ready\n")

        it "rejects unknown routes"
            $ responseForPath ["missing"]
            `shouldBe` (status404, "not found\n")
