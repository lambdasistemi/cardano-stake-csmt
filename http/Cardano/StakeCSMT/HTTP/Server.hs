{- |
Module      : Cardano.StakeCSMT.HTTP.Server
Description : WAI server for the scaffold API.

The server currently serves static health and readiness responses.
-}
module Cardano.StakeCSMT.HTTP.Server
    ( application
    , responseForPath
    , runHttpServer
    ) where

import Cardano.StakeCSMT.Application.Health
    ( healthStatus
    , readinessStatus
    )
import Cardano.StakeCSMT.HTTP.API
    ( Route (..)
    , routeForPath
    )
import Data.ByteString.Lazy (ByteString)
import Data.ByteString.Lazy qualified as ByteString.Lazy
import Data.Text (Text)
import Data.Text.Encoding qualified as Text
import Network.HTTP.Types
    ( Status
    , hContentType
    , status200
    , status404
    )
import Network.Wai
    ( Application
    , Response
    , pathInfo
    , responseLBS
    )
import Network.Wai.Handler.Warp qualified as Warp

application :: Application
application request respond =
    respond $ uncurry textResponse $ responseForPath $ pathInfo request

responseForPath :: [Text] -> (Status, ByteString)
responseForPath path =
    case routeForPath path of
        Just HealthRoute -> (status200, statusBody healthStatus)
        Just ReadyRoute -> (status200, statusBody readinessStatus)
        Nothing -> (status404, "not found\n")

runHttpServer :: Int -> IO ()
runHttpServer port = Warp.run port application

textResponse :: Status -> ByteString -> Response
textResponse status =
    responseLBS
        status
        [(hContentType, "text/plain; charset=utf-8")]

statusBody :: Text -> ByteString
statusBody =
    ByteString.Lazy.fromStrict . Text.encodeUtf8 . (<> "\n")
