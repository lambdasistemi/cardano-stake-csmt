{- |
Module      : Cardano.StakeCSMT.Application.Health
Description : Static health and readiness status values.

Initial service health surface for the stake CSMT scaffold.
-}
module Cardano.StakeCSMT.Application.Health
    ( healthStatus
    , readinessStatus
    ) where

import Data.Text (Text)

healthStatus :: Text
healthStatus = "ok"

readinessStatus :: Text
readinessStatus = "ready"
