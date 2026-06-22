module Cardano.StakeCSMT.HTTP.Base16Spec
    ( spec
    ) where

import Cardano.StakeCSMT.HTTP.Base16
    ( decodeBase16Text
    , encodeBase16Text
    , unsafeDecodeBase16Text
    )
import Data.ByteString qualified as BS
import Test.Hspec
    ( Spec
    , describe
    , it
    , shouldBe
    )

spec :: Spec
spec =
    describe "base16 helpers" $ do
        it "renders lowercase base16 text"
            $ encodeBase16Text (BS.pack [0, 10, 15, 16, 255])
            `shouldBe` "000a0f10ff"

        it "decodes valid base16 text"
            $ decodeBase16Text "000a0f10ff"
            `shouldBe` Right (BS.pack [0, 10, 15, 16, 255])

        it "rejects invalid base16 text"
            $ decodeBase16Text "not-base16"
            `shouldBe` Left "invalid base16"

        it "keeps the unsafe helper aligned with the checked decoder"
            $ unsafeDecodeBase16Text "000a"
            `shouldBe` BS.pack [0, 10]
