class Csv::ParseJob < ApplicationJob
  queue_as :default

  def perform(import_id)
    import = Csv::Import.find_by(id: import_id)
    return if import.nil?
    return unless import.file.attached?

    produced_indices = []
    import.file.open do |io|
      parser = Csv::Parser.new(io: io, mappings: import.column_mappings, currency: import.account.currency)
      parser.each_row do |parsed|
        record = Csv::Transaction
          .where(import_id: import.id, row_index: parsed.row_index)
          .first_or_initialize
        record.assign_attributes(
          transacted_at: parsed.transacted_at,
          posted_at: parsed.posted_at,
          description: parsed.description,
          amount_minor: parsed.amount_minor,
          raw: parsed.raw,
          synced_at: Time.current
        )
        record.save!
        produced_indices << parsed.row_index
      end
    end

    # Drop csv_transactions whose row_index is no longer produced by the
    # current mapping (e.g. user changed `skip_rows` after a previous parse).
    # `dependent: :destroy` on transaction_sources cleans up the join row; any
    # ledger transactions previously sourced from these rows simply lose their
    # CSV source and remain as ordinary ledger transactions.
    import.transactions.where.not(row_index: produced_indices).destroy_all

    import.update!(state: "parsed", parsed_at: Time.current, error: nil)
    # Always enqueue the import job — it no-ops when there are no rows but
    # still transitions the import to "imported", so a 0-row parse doesn't
    # leave the import permanently stuck in "parsed".
    Csv::ImportTransactionsJob.perform_later(import.id)
  rescue Csv::Parser::Error => e
    import&.update!(state: "failed", error: e.message)
  rescue StandardError => e
    import&.update!(state: "failed", error: "#{e.class}: #{e.message}")
    raise
  end
end
