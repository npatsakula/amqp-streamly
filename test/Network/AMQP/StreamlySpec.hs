{-# LANGUAGE OverloadedStrings #-}

module Network.AMQP.StreamlySpec
  ( main
  , spec
  )
where

import           Network.AMQP.Streamly

import           Control.Concurrent             ( threadDelay )
import           Control.Monad.IO.Class         ( liftIO )

import           Network.AMQP
import           Test.Hspec
import           TestContainers.Hspec
import qualified Data.ByteString.Lazy.Char8    as B
import           Data.Maybe                     ( fromJust )
import qualified Data.Text                     as T
import qualified Data.Text.Lazy                as TL
import           System.Process                 ( readProcess )
import qualified Streamly.Prelude              as S

main :: IO ()
main = hspec spec

spec :: Spec
spec =
  around (withContainers containers)
    $ it "producing 5 messages should be consumed in the right order"
    $ \channel -> flip shouldReturn messages $ do
        let arbitraryExchange   = "arbitraryExchange"
        let arbitraryRoutingKey = "arbitraryRoutingKey"
        let arbitraryQueue      = "arbitraryQueue"
        let fixedInstructions =
              SendInstructions arbitraryExchange arbitraryRoutingKey False
        liftIO $ declareExchange
          channel
          newExchange { exchangeName = arbitraryExchange
                      , exchangeType = "fanout"
                      }
        liftIO $ declareQueue channel newQueue { queueName = arbitraryQueue }
        liftIO $ bindQueue channel
                           arbitraryQueue
                           arbitraryExchange
                           arbitraryRoutingKey
        S.drain $ produce channel $ S.fromList $ map fixedInstructions messages
        S.toList
          (   S.take (length messages)
          $   fst
          <$> consume channel arbitraryQueue NoAck
          )

messages :: [Message]
messages = map toMessage ["Lorem", "ipsum", "dolor", "sit", "amet"]
 where
  toMessage x = Message (B.pack x)
                        Nothing
                        Nothing
                        Nothing
                        Nothing
                        Nothing
                        Nothing
                        Nothing
                        Nothing
                        Nothing
                        Nothing
                        Nothing
                        Nothing
                        Nothing
                        Nothing

mkChannel :: T.Text -> T.Text -> String -> IO Channel
mkChannel login password ip = do
  connection <- openConnection ip "/" login password
  openChannel connection

containers :: MonadDocker m => m Channel
containers = do
  let (login, password) = ("guest", "guest")
  container <- run $ containerRequest (fromTag "rabbitmq:3.8.4")
    & setWaitingFor (waitForLogLine Stdout (" completed with " `TL.isInfixOf`))
  liftIO $ mkChannel login password $ T.unpack $ containerIp container
