module Cardano.StakeCSMT.HTTP.ServerSpec
    ( spec
    ) where

import Cardano.Crypto.Hash.Class
    ( hashFromBytes
    )
import Cardano.Ledger.Coin
    ( Coin (..)
    )
import Cardano.Ledger.Credential
    ( Credential (KeyHashObj)
    )
import Cardano.Ledger.Keys
    ( KeyHash (..)
    , KeyRole (Staking)
    )
import Cardano.Slotting.Slot
    ( EpochNo (..)
    )
import Cardano.StakeCSMT.HTTP.API
    ( HistoryRootResponse (..)
    , ReadyResponse (..)
    , StakeProofResponse (..)
    , StakeRootResponse (..)
    , renderCredentialBase16
    )
import Cardano.StakeCSMT.HTTP.Server
    ( QueryHandlers (..)
    , apiApp
    )
import Data.ByteString qualified as BS
import Data.Text
    ( Text
    )
import Data.Text.Encoding qualified as Text
import Network.HTTP.Types
    ( methodGet
    , status200
    , status400
    , status404
    )
import Network.Wai
    ( requestMethod
    )
import Network.Wai.Test
    ( SResponse (..)
    , runSession
    )
import Network.Wai.Test qualified as WaiTest
import Test.Hspec
    ( Spec
    , describe
    , it
    , shouldBe
    )

spec :: Spec
spec = do
    describe "HTTP.Server apiApp static endpoints" $ do
        it "serves /health"
            $ do
                response <- get "/health" defaultHandlers
                WaiTest.simpleStatus response `shouldBe` status200
                WaiTest.simpleBody response `shouldBe` "ok"

        it "serves /ready"
            $ do
                response <- get "/ready" defaultHandlers
                WaiTest.simpleStatus response `shouldBe` status200
                WaiTest.simpleBody response `shouldBe` "{\"ready\":true}"

        it "rejects unknown routes"
            $ do
                response <- get "/missing" defaultHandlers
                WaiTest.simpleStatus response `shouldBe` status404

    describe "HTTP.Server apiApp proof and root handlers" $ do
        it "maps invalid credential base16/CBOR to 400" $ do
            response <- get "/proof/not-base16" defaultHandlers
            WaiTest.simpleStatus response `shouldBe` status400

        it "maps missing latest proof to 404" $ do
            response <-
                get
                    ("/proof/" <> renderCredentialBase16 testCredential)
                    defaultHandlers
                        { queryLatestProof = const $ pure Nothing
                        }
            WaiTest.simpleStatus response `shouldBe` status404

        it "maps missing historical proof to 404" $ do
            response <-
                get
                    ("/proof/42/" <> renderCredentialBase16 testCredential)
                    defaultHandlers
                        { queryHistoricalProof = \_ _ -> pure Nothing
                        }
            WaiTest.simpleStatus response `shouldBe` status404

        it "serves roots from the injected query action" $ do
            response <-
                get
                    "/roots"
                    defaultHandlers
                        { queryEpochRoots = pure [rootResponse]
                        }

            WaiTest.simpleStatus response `shouldBe` status200
            WaiTest.simpleBody response
                `shouldBe` "[{\"epoch\":42,\"stakeRoot\":\"abcd\",\"totalStake\":60}]"

        it "maps missing history root to 404" $ do
            response <-
                get
                    "/history-root"
                    defaultHandlers
                        { queryHistoryRoot = pure Nothing
                        }
            WaiTest.simpleStatus response `shouldBe` status404

        it "serves history root from the injected query action" $ do
            response <-
                get
                    "/history-root"
                    defaultHandlers
                        { queryHistoryRoot =
                            pure $ Just HistoryRootResponse{historyRoot = "abcd"}
                        }
            WaiTest.simpleStatus response `shouldBe` status200
            WaiTest.simpleBody response `shouldBe` "{\"historyRoot\":\"abcd\"}"

get :: Text -> QueryHandlers -> IO SResponse
get path handlers =
    runSession
        ( WaiTest.request
            $ WaiTest.setPath
                WaiTest.defaultRequest{requestMethod = methodGet}
                (Text.encodeUtf8 path)
        )
        (apiApp handlers)

defaultHandlers :: QueryHandlers
defaultHandlers =
    QueryHandlers
        { queryLatestProof = const $ pure $ Just proofResponse
        , queryHistoricalProof = \_ _ -> pure $ Just proofResponse
        , queryEpochRoots = pure []
        , queryHistoryRoot =
            pure $ Just HistoryRootResponse{historyRoot = "abcd"}
        , queryReady = pure ReadyResponse{ready = True}
        }

proofResponse :: StakeProofResponse
proofResponse =
    StakeProofResponse
        { epoch = EpochNo 42
        , credential = renderCredentialBase16 testCredential
        , stake = Coin 10
        , stakeRoot = "abcd"
        , totalStake = Coin 60
        , proofBytes = "0011"
        }

rootResponse :: StakeRootResponse
rootResponse =
    StakeRootResponse
        { epoch = EpochNo 42
        , stakeRoot = "abcd"
        , totalStake = Coin 60
        }

testCredential :: Credential Staking
testCredential =
    case hashFromBytes $ BS.replicate 28 7 of
        Nothing -> error "invalid deterministic key hash bytes"
        Just keyHash -> KeyHashObj $ KeyHash keyHash
