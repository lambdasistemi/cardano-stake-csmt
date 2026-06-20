module Main
    ( main
    ) where

import Cardano.StakeCSMT.Application.HealthSpec qualified as HealthSpec
import Cardano.StakeCSMT.HTTP.ServerSpec qualified as ServerSpec
import Test.Hspec (hspec)

main :: IO ()
main = hspec $ do
    HealthSpec.spec
    ServerSpec.spec
