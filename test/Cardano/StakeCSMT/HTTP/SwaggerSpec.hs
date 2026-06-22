module Cardano.StakeCSMT.HTTP.SwaggerSpec
    ( spec
    ) where

import Cardano.StakeCSMT.HTTP.Swagger
    ( renderSwaggerJSON
    )
import Data.Aeson
    ( Value (Object, String)
    , eitherDecode
    )
import Data.Aeson.Key qualified as Key
import Data.Aeson.KeyMap qualified as KeyMap
import Data.ByteString.Lazy qualified as ByteString.Lazy
import Test.Hspec
    ( Spec
    , describe
    , it
    , shouldBe
    , shouldSatisfy
    )

spec :: Spec
spec =
    describe "HTTP.Swagger"
        $ it "renders OpenAPI JSON for the proof and status endpoints"
        $ do
            ByteString.Lazy.length renderSwaggerJSON
                `shouldSatisfy` (> 0)

            case eitherDecode renderSwaggerJSON of
                Left err -> fail err
                Right value -> do
                    lookupPath ["paths", "/proof/{credential}"] value
                        `shouldSatisfy` isObject
                    lookupPath ["paths", "/ready"] value
                        `shouldSatisfy` isObject
                    lookupPath ["paths", "/metrics"] value
                        `shouldSatisfy` isObject
                    lookupPath ["info", "title"] value
                        `shouldBe` Just (String "Cardano Stake CSMT API")

lookupPath :: [Key.Key] -> Value -> Maybe Value
lookupPath [] value = Just value
lookupPath (key : keys) (Object object) =
    KeyMap.lookup key object >>= lookupPath keys
lookupPath (_ : _) _ = Nothing

isObject :: Maybe Value -> Bool
isObject = \case
    Just Object{} -> True
    _ -> False
