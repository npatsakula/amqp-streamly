{-# LANGUAGE OverloadedStrings #-}

module Network.AMQP.StreamlySpec (main, spec) where

import Network.AMQP.Streamly

import Control.Concurrent(threadDelay)
import Control.Exception(bracket)
import Control.Monad.IO.Class(liftIO)

import Docker.Client
import Network.AMQP
import Test.Hspec
import qualified Data.ByteString.Lazy.Char8 as B
import qualified Data.Text as T
import qualified Streamly.Prelude as S

main :: IO ()
main = hspec spec

spec :: Spec
spec = around withChannel $
  it "producing 5 messages should be consumed in the right order" $ \(_, channel) ->
    flip shouldReturn messages $ do
      let arbitraryExchange = "arbitraryExchange"
      let arbitraryRoutingKey = "arbitraryRoutingKey"
      let arbitraryQueue = "arbitraryQueue"
      let fixedInstructions = SendInstructions arbitraryExchange arbitraryRoutingKey True
      liftIO $ declareExchange channel newExchange { exchangeName = arbitraryExchange, exchangeType = "fanout" }
      liftIO $ declareQueue channel newQueue { queueName = arbitraryQueue }
      liftIO $ bindQueue channel arbitraryQueue arbitraryQueue arbitraryRoutingKey
      S.drain $ produce channel $ S.fromList $ map fixedInstructions messages
      S.toList (S.take (length messages) $ fst <$> consume channel arbitraryQueue Ack)

messages :: [Message]
messages = map toMessage ["Lorem", "ipsum", "dolor", "sit", "amet"]
  where toMessage x = Message (B.pack x) Nothing Nothing Nothing Nothing Nothing Nothing Nothing Nothing Nothing Nothing Nothing Nothing Nothing Nothing

open :: IO ((ContainerID, Connection), Channel)
open = do
  let (login, password) = ("streamly", "stream")
  (containerId, containerDetails) <- runRabbitMQContainer login password
  let hostName = T.unpack $ networkSettingsIpAddress $ networkSettings containerDetails
  connection <- openConnection hostName "/" login password
  channel <- openChannel connection
  return ((containerId, connection), channel)

runRabbitMQContainer :: T.Text -> T.Text -> IO (ContainerID, ContainerDetails)
runRabbitMQContainer login password = do
    h <- defaultHttpHandler
    runDockerT (defaultClientOpts, h) $ do
      let envVars = [EnvVar "RABBITMQ_DEFAULT_USER" login, EnvVar "RABBITMQ_DEFAULT_PASS" password]
      let baseCreationOptions = defaultCreateOpts "rabbitmq:3.8.4"
      let creationOptions = baseCreationOptions { containerConfig = (containerConfig baseCreationOptions) { env = envVars <> env (containerConfig baseCreationOptions) } }
      cid <- createContainer creationOptions Nothing
      case cid of
          Left err -> error $ show err
          Right containerId -> do
              _ <- startContainer defaultStartOpts containerId
              containerDetails <- fetchContainerDetails containerId
              return (containerId, containerDetails)

fetchContainerDetails containerId = do
  details <- inspectContainer containerId
  case details of
    Right x -> return x
    Left _  -> do
      liftIO $ threadDelay 1000000
      fetchContainerDetails containerId

close :: ((ContainerID, Connection), Channel) -> IO ()
close ((containerId, connection), channel) = do
  stopRabbitMQContainer containerId
  closeChannel channel
  closeConnection connection

stopRabbitMQContainer :: ContainerID -> IO ()
stopRabbitMQContainer cid = do
    h <- defaultHttpHandler
    runDockerT (defaultClientOpts, h) $ do
      r <- stopContainer DefaultTimeout cid
      case r of
          Left err -> error "I failed to stop the container"
          Right _ -> return ()

withChannel :: (((ContainerID, Connection), Channel) -> IO ()) -> IO ()
withChannel = bracket open close
