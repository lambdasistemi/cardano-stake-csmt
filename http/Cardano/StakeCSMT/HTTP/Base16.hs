module Cardano.StakeCSMT.HTTP.Base16
    ( encodeBase16Text
    , decodeBase16Text
    , unsafeDecodeBase16Text
    ) where

import Data.ByteString
    ( ByteString
    )
import Data.ByteString.Base16 qualified as Base16
import Data.Text
    ( Text
    )
import Data.Text.Encoding qualified as Text

encodeBase16Text :: ByteString -> Text
encodeBase16Text =
    Text.decodeUtf8 . Base16.encode

decodeBase16Text :: Text -> Either String ByteString
decodeBase16Text text =
    case Base16.decode $ Text.encodeUtf8 text of
        Right bytes -> Right bytes
        Left _ -> Left "invalid base16"

unsafeDecodeBase16Text :: Text -> ByteString
unsafeDecodeBase16Text text =
    case decodeBase16Text text of
        Right bytes -> bytes
        Left err -> error $ "unsafeDecodeBase16Text: " <> err
