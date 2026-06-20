{- |
Module      : Cardano.StakeCSMT.HTTP.API
Description : HTTP route model for the scaffold API.

The initial API intentionally exposes only health and readiness routes.
-}
module Cardano.StakeCSMT.HTTP.API
    ( Route (..)
    , routeForPath
    ) where

import Data.Text (Text)

data Route
    = HealthRoute
    | ReadyRoute
    deriving stock (Eq, Show)

routeForPath :: [Text] -> Maybe Route
routeForPath = \case
    ["health"] -> Just HealthRoute
    ["ready"] -> Just ReadyRoute
    _ -> Nothing
