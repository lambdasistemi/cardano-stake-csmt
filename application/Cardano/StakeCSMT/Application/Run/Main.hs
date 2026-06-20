{- |
Module      : Cardano.StakeCSMT.Application.Run.Main
Description : Application entrypoint wiring.

Runs the scaffold HTTP server with static health and readiness routes.
-}
module Cardano.StakeCSMT.Application.Run.Main
    ( main
    , run
    ) where

import Cardano.StakeCSMT.Application.Run.Config
    ( RuntimeConfig (..)
    , defaultConfig
    )
import Cardano.StakeCSMT.HTTP.Server
    ( runHttpServer
    )

main :: IO ()
main = run defaultConfig

run :: RuntimeConfig -> IO ()
run RuntimeConfig{configPort} = runHttpServer configPort
