# frozen_string_literal: true

class Pubsubhubbub::DistributionWorker
  include Sidekiq::Worker

  sidekiq_options queue: 'push'

  def perform(stream_entry_id)
    stream_entry = StreamEntry.find(stream_entry_id)

    return if stream_entry.status&.direct_visibility?
    return if stream_entry.status&.local? && TimeLimit.from_tags(stream_entry.status&.tags)
    return if stream_entry.status&.reblog? && stream_entry.status.reblog.local? && TimeLimit.from_tags(stream_entry.status.reblog.tags)

    account = stream_entry.account
    payload = AtomSerializer.render(AtomSerializer.new.feed(account, [stream_entry]))
    domains = account.followers_domains

    Subscription.where(account: account).active.select('id, callback_url').find_each do |subscription|
      next unless domains.include?(Addressable::URI.parse(subscription.callback_url).host)
      Pubsubhubbub::DeliveryWorker.perform_async(subscription.id, payload)
    end
  rescue ActiveRecord::RecordNotFound
    true
  end
end
