module Cardano.StakeCSMT.HTTP.APISpec
    ( spec
    ) where

import CSMT.Hashes
    ( Hash
    )
import Cardano.Crypto.Hash
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
import Cardano.StakeCSMT.CSMT.Codecs
    ( csmtHashCodec
    )
import Cardano.StakeCSMT.HTTP.API
    ( LatestHeaderResponse (..)
    , ReadyResponse (..)
    , StakeProofResponse (..)
    , StakeRootResponse (..)
    , parseCredentialBase16
    , renderCredentialBase16
    , renderHashBase16
    )
import Control.Lens
    ( preview
    )
import Data.Aeson
    ( Value (Object)
    , encode
    , object
    , toJSON
    , (.=)
    )
import Data.Aeson.Key qualified as Key
import Data.Aeson.KeyMap qualified as KeyMap
import Data.ByteString qualified as BS
import Data.Text
    ( Text
    )
import Test.Hspec
    ( Spec
    , describe
    , it
    , shouldBe
    , shouldSatisfy
    )

spec :: Spec
spec = do
    describe "stake API JSON contract" $ do
        it "renders proof fields with stable wire names" $ do
            let proof =
                    StakeProofResponse
                        { epoch = EpochNo 42
                        , credential = renderCredentialBase16 testCredential
                        , stake = Coin 1_000_000
                        , stakeRoot = renderHashBase16 testHash
                        , totalStake = Coin 2_000_000
                        , proofBytes = "00ff"
                        }

            jsonKeys (toJSON proof)
                `shouldBe` [ "credential"
                           , "epoch"
                           , "proofBytes"
                           , "stake"
                           , "stakeRoot"
                           , "totalStake"
                           ]

            encode proof
                `shouldBe` encode
                    ( object
                        [ "epoch" .= (42 :: Word)
                        , "credential" .= renderCredentialBase16 testCredential
                        , "stake" .= (1_000_000 :: Integer)
                        , "stakeRoot" .= renderHashBase16 testHash
                        , "totalStake" .= (2_000_000 :: Integer)
                        , "proofBytes" .= ("00ff" :: Text)
                        ]
                    )

        it "renders root fields with stable wire names" $ do
            let root =
                    StakeRootResponse
                        { epoch = EpochNo 42
                        , stakeRoot = renderHashBase16 testHash
                        , totalStake = Coin 2_000_000
                        }

            jsonKeys (toJSON root)
                `shouldBe` ["epoch", "stakeRoot", "totalStake"]

        it "renders signed latest-header fields with stable wire names" $ do
            let header =
                    LatestHeaderResponse
                        { epoch = EpochNo 42
                        , stakeRoot = renderHashBase16 testHash
                        , totalStake = Coin 2_000_000
                        , signature = "cafe"
                        , publicKey = "beef"
                        }

            jsonKeys (toJSON header)
                `shouldBe` [ "epoch"
                           , "publicKey"
                           , "signature"
                           , "stakeRoot"
                           , "totalStake"
                           ]

            encode header
                `shouldBe` encode
                    ( object
                        [ "epoch" .= (42 :: Word)
                        , "stakeRoot" .= renderHashBase16 testHash
                        , "totalStake" .= (2_000_000 :: Integer)
                        , "signature" .= ("cafe" :: Text)
                        , "publicKey" .= ("beef" :: Text)
                        ]
                    )

        it "rejects invalid credential base16/CBOR"
            $ parseCredentialBase16 "00"
            `shouldSatisfy` isLeft

        it "renders readiness as JSON"
            $ toJSON (ReadyResponse True)
            `shouldBe` object ["ready" .= True]

    describe "stake API wire codecs"
        $ it "round-trips credential base16"
        $ parseCredentialBase16 (renderCredentialBase16 testCredential)
        `shouldBe` Right testCredential

jsonKeys :: Value -> [Text]
jsonKeys = \case
    Object obj -> Key.toText <$> KeyMap.keys obj
    _ -> []

isLeft :: Either a b -> Bool
isLeft = \case
    Left _ -> True
    Right _ -> False

testCredential :: Credential Staking
testCredential =
    case hashFromBytes $ BS.replicate 28 7 of
        Nothing -> error "invalid deterministic key hash bytes"
        Just keyHash -> KeyHashObj $ KeyHash keyHash

testHash :: Hash
testHash =
    case preview csmtHashCodec $ BS.pack [0 .. 31] of
        Nothing -> error "invalid deterministic CSMT hash bytes"
        Just hash -> hash
