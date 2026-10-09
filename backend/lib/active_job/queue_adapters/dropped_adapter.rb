module ActiveJob
  module QueueAdapters
    class DroppedAdapter < AbstractAdapter
      def enqueue(job)
        Rails.logger.info("[jobs off] dropped #{job.class.name} #{job.arguments.inspect}")
      end

      def enqueue_at(job, _timestamp)
        enqueue(job)
      end
    end
  end
end
