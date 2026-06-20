module Cardano.StakeCSMT.Application.HealthSpec
    ( spec
    ) where

import Cardano.StakeCSMT.Application.Health
    ( healthStatus
    , readinessStatus
    )
import Test.Hspec
    ( Spec
    , describe
    , it
    , shouldBe
    )

spec :: Spec
spec = do
    describe "healthStatus"
        $ it "reports the service as healthy"
        $ healthStatus
        `shouldBe` "ok"

    describe "readinessStatus"
        $ it "reports the service as ready"
        $ readinessStatus
        `shouldBe` "ready"
