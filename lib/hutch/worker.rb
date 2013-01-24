require 'amqp'
require 'hutch/message'
require 'hutch/logging'

module Hutch
  class Worker
    include Logging

    def initialize(consumers)
      @consumers = consumers
    end

    # Run the main event loop. The consumers will be set up with queues, and
    # process the messages in their respective queues indefinitely. This method
    # never returns.
    def run
      logger.info 'booting eventmachine'
      EventMachine.run do
        # TODO: make these configurable
        host, port, exchange = '127.0.0.1', 5672, 'hutch.dev'
        logger.info "connecting to rabbitmq (#{host}:#{port})"
        @connection = AMQP.connect(host: host, port: port)
        @channel    = AMQP::Channel.new(@connection)
        @exchange   = @channel.topic(exchange)
        logger.info "rabbitmq channel open, using exchange #{exchange}"

        setup_queues
        logger.info 'set up queues, hutch is open for business'
      end
    end

    # Set up the queues for each of the worker's consumers.
    def setup_queues
      @consumers.each { |consumer| setup_queue(consumer) }
    end

    # Bind a consumer's routing keys to its queue, and set up a subscription to
    # receive messages sent to the queue.
    def setup_queue(consumer)
      queue = consumer_queue(consumer)

      consumer.routing_keys.each do |routing_key|
        queue.bind(@exchange, routing_key: routing_key)
      end

      queue.subscribe do |metadata, payload|
        handle_message(consumer, metadata, payload)
      end
    end

    # Get / create the RabbitMQ queue for a given consumer.
    def consumer_queue(consumer)
      @channel.queue(consumer.queue_name)
    end

    # Called internally when a new messages comes in from RabbitMQ. Responsible
    # for wrapping up the message and passing it to the consumer.
    def handle_message(consumer, metadata, payload)
      logger.info("message(#{metadata.message_id || '-'}): " +
                  "routing key: #{metadata.routing_key}, " +
                  "consumer: #{consumer}, " +
                  "payload: #{payload}")

      message = Message.new(metadata, payload)
      consumer.new.process(message)
    end
  end
end