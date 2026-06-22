{- |
Module      : Cardano.StakeCSMT.HTTP.Swagger
Description : OpenAPI and Swagger UI support for the stake CSMT API.

Generates the OpenAPI document for the stake proof HTTP API and serves it
through the standard Swagger UI servant application.
-}
module Cardano.StakeCSMT.HTTP.Swagger
    ( SwaggerAPI
    , swaggerDoc
    , swaggerServer
    , renderSwaggerJSON
    ) where

import Cardano.StakeCSMT.HTTP.API
    ( api
    )
import Control.Lens
    ( (&)
    , (.~)
    , (?~)
    )
import Data.Aeson.Encode.Pretty
    ( encodePretty
    )
import Data.ByteString.Lazy
    ( ByteString
    )
import Data.Swagger
    ( Host (..)
    , Swagger
    , description
    , host
    , info
    , license
    , title
    , version
    )
import Network.Socket
    ( PortNumber
    )
import Servant
    ( Server
    )
import Servant.Swagger
    ( toSwagger
    )
import Servant.Swagger.UI
    ( SwaggerSchemaUI
    )
import Servant.Swagger.UI qualified as SwaggerUI

type SwaggerAPI = SwaggerSchemaUI "swagger-ui" "swagger.json"

-- | Generate the OpenAPI document for the stake CSMT API.
swaggerDoc :: Maybe Host -> Swagger
swaggerDoc mHost =
    toSwagger api
        & info . title .~ "Cardano Stake CSMT API"
        & info . version .~ "0.1.0.0"
        & info . description
            ?~ "HTTP API for querying stake CSMT inclusion proofs, \
               \epoch roots, history roots, and service status."
        & info . license ?~ "Apache 2.0"
        & host .~ mHost

-- | Servant server for Swagger UI and its schema endpoint.
swaggerServer :: Maybe PortNumber -> Server SwaggerAPI
swaggerServer mApiPort =
    SwaggerUI.swaggerSchemaUIServer $ swaggerDoc mHost
  where
    mHost =
        fmap
            (\port -> Host{_hostName = "localhost", _hostPort = Just port})
            mApiPort

-- | Render the OpenAPI document as pretty JSON.
renderSwaggerJSON :: ByteString
renderSwaggerJSON =
    encodePretty $ swaggerDoc Nothing
