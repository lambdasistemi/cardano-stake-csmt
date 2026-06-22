{- |
Module      : Cardano.StakeCSMT.HTTP.Server
Description : WAI server for the stake CSMT HTTP API.
-}
module Cardano.StakeCSMT.HTTP.Server
    ( application
    , apiApp
    , apiServer
    , QueryHandlers (..)
    , responseForPath
    , runHttpServer
    ) where

import Cardano.Ledger.Credential
    ( Credential
    )
import Cardano.Ledger.Keys
    ( KeyRole (Staking)
    )
import Cardano.Slotting.Slot
    ( EpochNo (EpochNo)
    )
import Cardano.StakeCSMT.Application.Health
    ( healthStatus
    )
import Cardano.StakeCSMT.HTTP.API
    ( API
    , HistoryRootResponse
    , MetricsResponse (..)
    , ReadyResponse (..)
    , StakeProofResponse
    , StakeRootResponse
    , api
    , parseCredentialBase16
    )
import Control.Exception
    ( Exception
    , throwIO
    , try
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
import Data.Text qualified as Text
import Data.Text.Encoding qualified as Text.Encoding
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
    , err400
    , err404
    , err503
    , errBody
    , serve
    , throwError
    , (:<|>) (..)
    )

data QueryHandlers = QueryHandlers
    { queryLatestProof
        :: Credential Staking -> IO (Maybe StakeProofResponse)
    , queryHistoricalProof
        :: EpochNo -> Credential Staking -> IO (Maybe StakeProofResponse)
    , queryEpochRoots :: IO [StakeRootResponse]
    , queryHistoryRoot :: IO (Maybe HistoryRootResponse)
    , queryReady :: IO ReadyResponse
    }

application :: Application
application =
    apiApp unavailableHandlers

apiApp :: QueryHandlers -> Application
apiApp handlers =
    serve api $ apiServer handlers

apiServer :: QueryHandlers -> Server API
apiServer QueryHandlers{..} =
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
        liftIO queryReady

    metricsHandler :: Handler MetricsResponse
    metricsHandler = do
        ReadyResponse{ready} <- liftIO queryReady
        pure MetricsResponse{ready, latestEpoch = Nothing}

    latestProofHandler credentialText =
        withCredential credentialText $ \credential -> do
            mProof <- runQuery $ queryLatestProof credential
            maybe (throwError err404) pure mProof

    historicalProofHandler epoch credentialText =
        withCredential credentialText $ \credential -> do
            mProof <-
                runQuery
                    $ queryHistoricalProof
                        (EpochNo $ fromIntegral epoch)
                        credential
            maybe (throwError err404) pure mProof

    rootsHandler =
        runQuery queryEpochRoots

    historyRootHandler =
        runQuery queryHistoryRoot >>= maybe (throwError err404) pure

withCredential
    :: Text
    -> (Credential Staking -> Handler a)
    -> Handler a
withCredential credentialText action =
    case parseCredentialBase16 credentialText of
        Left err ->
            throwError
                err400
                    { errBody =
                        ByteString.Lazy.fromStrict
                            $ Text.Encoding.encodeUtf8
                            $ "invalid credential: " <> Text.pack err
                    }
        Right credential -> action credential

runQuery :: IO a -> Handler a
runQuery action = do
    result <- liftIO $ try action
    case result of
        Left QueryBackendUnavailable ->
            throwError
                err503
                    { errBody =
                        "stake proof query backend is not configured"
                    }
        Right value -> pure value

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
    ByteString.Lazy.fromStrict . Text.Encoding.encodeUtf8 . (<> "\n")

data QueryBackendUnavailable = QueryBackendUnavailable
    deriving stock (Show)

instance Exception QueryBackendUnavailable

unavailableHandlers :: QueryHandlers
unavailableHandlers =
    QueryHandlers
        { queryLatestProof = const unavailable
        , queryHistoricalProof = \_ _ -> unavailable
        , queryEpochRoots = unavailable
        , queryHistoryRoot = unavailable
        , queryReady = pure ReadyResponse{ready = True}
        }

unavailable :: IO a
unavailable =
    throwIO QueryBackendUnavailable
