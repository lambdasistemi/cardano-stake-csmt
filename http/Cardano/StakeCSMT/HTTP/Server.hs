{- |
Module      : Cardano.StakeCSMT.HTTP.Server
Description : WAI server for the stake CSMT HTTP API.
-}
module Cardano.StakeCSMT.HTTP.Server
    ( application
    , apiApp
    , apiServer
    , responseForPath
    , runHttpServer
    ) where

import Cardano.StakeCSMT.Application.Health
    ( healthStatus
    )
import Cardano.StakeCSMT.HTTP.API
    ( API
    , MetricsResponse (..)
    , ReadyResponse (..)
    , api
    )
import Control.Monad.IO.Class
    ( liftIO
    )
import Data.Aeson
    ( encode
    )
import Data.ByteString.Lazy (ByteString)
import Data.ByteString.Lazy qualified as ByteString.Lazy
import Data.Text (Text)
import Data.Text.Encoding qualified as Text
import Network.HTTP.Types
    ( Status
    , status200
    , status404
    )
import Network.Wai
    ( Application
    )
import Network.Wai.Handler.Warp qualified as Warp
import Servant
    ( Handler
    , Server
    , ServerError (..)
    , errBody
    , serve
    , throwError
    , (:<|>) (..)
    )

application :: Application
application =
    apiApp (pure $ ReadyResponse True)

apiApp :: IO ReadyResponse -> Application
apiApp getReady =
    serve api $ apiServer getReady

apiServer :: IO ReadyResponse -> Server API
apiServer getReady =
    pure healthStatus
        :<|> latestProofHandler
        :<|> historicalProofHandler
        :<|> rootsHandler
        :<|> historyRootHandler
        :<|> readyHandler
        :<|> metricsHandler
  where
    readyHandler :: Handler ReadyResponse
    readyHandler =
        liftIO getReady

    metricsHandler :: Handler MetricsResponse
    metricsHandler = do
        ReadyResponse{ready} <- liftIO getReady
        pure MetricsResponse{ready, latestEpoch = Nothing}

    latestProofHandler _credential =
        throwError notImplemented

    historicalProofHandler _epoch _credential =
        throwError notImplemented

    rootsHandler =
        throwError notImplemented

    historyRootHandler =
        throwError notImplemented

    notImplemented :: ServerError
    notImplemented =
        ServerError
            { errHTTPCode = 501
            , errReasonPhrase = "Not Implemented"
            , errBody = "stake proof queries are implemented in a later slice"
            , errHeaders = []
            }

{- | Direct response helper retained for focused scaffold tests.

The WAI application is servant-backed; this helper mirrors the same static
readiness contract without needing to run a request.
-}
responseForPath :: [Text] -> (Status, ByteString)
responseForPath = \case
    ["health"] -> (status200, statusBody healthStatus)
    ["ready"] -> (status200, encode $ ReadyResponse True)
    _ -> (status404, "not found\n")

runHttpServer :: Int -> IO ()
runHttpServer port = Warp.run port application

statusBody :: Text -> ByteString
statusBody =
    ByteString.Lazy.fromStrict . Text.encodeUtf8 . (<> "\n")
