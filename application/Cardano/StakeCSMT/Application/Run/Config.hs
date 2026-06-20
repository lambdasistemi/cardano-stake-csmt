{- |
Module      : Cardano.StakeCSMT.Application.Run.Config
Description : Runtime configuration for the scaffold executable.

Only the HTTP port is configurable in the initial scaffold.
-}
module Cardano.StakeCSMT.Application.Run.Config
    ( RuntimeConfig (..)
    , defaultConfig
    ) where

newtype RuntimeConfig = RuntimeConfig
    { configPort :: Int
    }
    deriving stock (Eq, Show)

defaultConfig :: RuntimeConfig
defaultConfig = RuntimeConfig{configPort = 8080}
