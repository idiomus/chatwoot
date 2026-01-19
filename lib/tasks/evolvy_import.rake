# frozen_string_literal: true

# Evolvy to Chatwoot Migration
# See docs/evolvy-migration.md for full documentation

namespace :evolvy do
  desc 'Show statistics about Evolvy dump without importing'
  task dry_run: :environment do
    importer = EvolvyImporter.new
    importer.dry_run
  end

  desc 'Import data from Evolvy JSON dump'
  task import: :environment do
    importer = EvolvyImporter.new
    importer.import
  end

  desc 'Validate imported data'
  task validate: :environment do
    importer = EvolvyImporter.new
    importer.validate
  end

  desc 'Validate agent mapping against source data (proves sender attribution will work in production)'
  task validate_senders: :environment do
    importer = EvolvyImporter.new
    importer.validate_sender_mapping
  end

  desc 'Create ex-employee users for historical data preservation (run before import in production)'
  task create_ex_employees: :environment do
    importer = EvolvyImporter.new
    importer.create_ex_employee_users
  end

  desc 'Import only contacts from Evolvy'
  task import_contacts: :environment do
    importer = EvolvyImporter.new
    importer.import_contacts_only
  end

  desc 'Import only conversations from Evolvy'
  task import_conversations: :environment do
    importer = EvolvyImporter.new
    importer.import_conversations_only
  end

  desc 'Test import with limited data (use LIMIT_CONVERSATIONS=100, LIMIT_INBOX=13726)'
  task test_import: :environment do
    importer = EvolvyImporter.new(test_mode: true)
    importer.import
  end

  desc 'Cleanup duplicate messages from test imports (keeps oldest by ID)'
  task cleanup_duplicates: :environment do
    importer = EvolvyImporter.new
    importer.cleanup_duplicate_messages
  end

  desc 'Show duplicate statistics without deleting'
  task show_duplicates: :environment do
    importer = EvolvyImporter.new
    importer.show_duplicate_stats
  end

  desc 'Cleanup duplicate conversations from test imports (keeps one with most messages)'
  task cleanup_duplicate_conversations: :environment do
    importer = EvolvyImporter.new
    importer.cleanup_duplicate_conversations
  end

  desc 'Delete ALL data from a specific inbox (use INBOX_ID=1). WARNING: Destructive!'
  task cleanup_inbox: :environment do
    inbox_id = ENV.fetch('INBOX_ID', nil)&.to_i
    raise 'INBOX_ID environment variable is required' unless inbox_id

    importer = EvolvyImporter.new
    importer.cleanup_inbox(inbox_id)
  end

  desc 'Delete ALL Evolvy-imported conversations (has evolvy_id). Use to retry failed imports.'
  task cleanup_evolvy_imports: :environment do
    importer = EvolvyImporter.new
    importer.cleanup_evolvy_imports
  end

  desc 'Import attachments for already-imported messages (use TARGET_INBOX for parallel)'
  task import_attachments: :environment do
    importer = EvolvyImporter.new
    importer.import_attachments_only
  end

  desc 'Import attachments using parallel threads for faster processing. THREADS=N (default: CPU count)'
  task import_attachments_parallel: :environment do
    require 'concurrent'
    importer = EvolvyImporter.new
    importer.import_attachments_parallel
  end

  desc 'Import specific conversations by Evolvy ID. Usage: CONV_IDS=205450,242705 rake evolvy:import_specific'
  task import_specific: :environment do
    conv_ids = ENV['CONV_IDS']&.split(',')&.map(&:to_i)
    if conv_ids.blank?
      puts "Usage: CONV_IDS=205450,242705 rake evolvy:import_specific"
      exit 1
    end
    importer = EvolvyImporter.new
    importer.import_specific_conversations(conv_ids)
  end

  desc 'Import missing conversations from CSV verification file. Usage: CSV_FILE=/path/to/file.csv rake evolvy:import_from_csv'
  task import_from_csv: :environment do
    csv_file = ENV.fetch('CSV_FILE', '/home/tarzan/Documents/programing/idiomus/chatwoot/todas_conversas_status.csv')
    log_file = ENV.fetch('LOG_FILE', "/home/tarzan/Documents/programing/idiomus/chatwoot/import_missing_#{Time.now.strftime('%Y%m%d_%H%M%S')}.log")

    unless File.exist?(csv_file)
      puts "CSV file not found: #{csv_file}"
      exit 1
    end

    importer = EvolvyImporter.new
    importer.import_from_csv_with_logging(csv_file, log_file)
  end

  desc 'Reimport messages for conversations that have no messages. Usage: rake evolvy:reimport_messages'
  task reimport_messages: :environment do
    log_file = ENV.fetch('LOG_FILE', "/home/tarzan/Documents/programing/idiomus/chatwoot/reimport_msgs_#{Time.now.strftime('%Y%m%d_%H%M%S')}.log")
    importer = EvolvyImporter.new
    importer.reimport_messages_for_empty_conversations(log_file)
  end
end

class EvolvyImporter
  DUMP_PATH = ENV.fetch('EVOLVY_DUMP_PATH', Rails.root.join('06_01_2026_evolvy_dump'))
  ACCOUNT_ID = ENV.fetch('CHATWOOT_ACCOUNT_ID', 1).to_i
  BATCH_SIZE = ENV.fetch('IMPORT_BATCH_SIZE', 1000).to_i

  # Limits for test mode
  LIMIT_INBOX = ENV['LIMIT_INBOX']&.to_i
  LIMIT_CONVERSATIONS = ENV.fetch('LIMIT_CONVERSATIONS', 100).to_i
  LIMIT_CONTACTS = ENV.fetch('LIMIT_CONTACTS', 500).to_i

  # Cutoff date to avoid overlap with webhook data (format: YYYY-MM-DD)
  # Only import conversations created BEFORE this date
  CUTOFF_DATE = ENV['CUTOFF_DATE'] ? Date.parse(ENV['CUTOFF_DATE']) : nil

  # Skip attachment import (track references in manifest only)
  SKIP_ATTACHMENTS = ENV['SKIP_ATTACHMENTS'] == 'true'

  # Skip contact import (for parallel runs where contacts already imported)
  SKIP_CONTACTS = ENV['SKIP_CONTACTS'] == 'true'

  # Target specific Chatwoot inbox (for parallel imports by inbox)
  # When set, only imports conversations that map to this inbox
  TARGET_INBOX = ENV['TARGET_INBOX']&.to_i

  # Evolvy inbox_id => Chatwoot inbox_id
  #
  # Chatwoot inboxes:
  #   1  = Histórico Evolvy (inactive numbers archive)
  #   7  = Idiomus (API)
  #   8  = Teacher Poli (API) - Facebook
  #   9  = Teacher Poli Latam (API) - Facebook
  #   10 = Suporte Oficial (WhatsApp) - +558393940644
  #   11 = Grupo Idiomus - Teacher Poli (API) - +5541998660291
  #
  # nil = skip (emails sync via IMAP)
  #
  INBOX_MAPPING = {
    # ─── Teacher Poli WhatsApp → Chatwoot 11 (Grupo Idiomus - Teacher Poli)
    5601   => 11,  # (83) 92000-5321   │ 6,961 convs
    13_726 => 11,  # (41) 99866-0291   │ 22,186 convs (main line)
    13_984 => 11,  # (41) 98765-0291   │ 8,927 convs

    # ─── Teacher Poli Facebook → Chatwoot 8 (Teacher Poli)
    14_515 => 8,   # Facebook          │ 4,248 convs

    # ─── Teacher Poli Latam → Chatwoot 9 (Teacher Poli Latam)
    14_535 => 9,   # Facebook (ES)     │ 1,960 convs

    # ─── Idiomus Facebook → Chatwoot 7 (Idiomus)
    5608   => 7,   # Idiomus App       │ 23 convs
    5871   => 7,   # Idiomus           │ 8,348 convs

    # ─── Suporte Oficial → Chatwoot 10 (Suporte Oficial)
    14_483 => 10,  # API Oficial       │ 12,765 convs
    14_450 => 10,  # Onboarding API    │ 11 convs

    # ─── Histórico Evolvy → Chatwoot 1 (inactive numbers archive)
    5598   => 1,   # (41) 99907-1709   │ 26,179 convs (inactive)
    5599   => 1,   # (84) 99411-8931   │ 5,336 convs (inactive)
    5600   => 1,   # (83) 99115-3226   │ 8,269 convs (Onboarding, inactive)

    # ─── Emails (histórico importado do dump)
    13_536 => nil, # Teste Nivelamento │ 0 convs (sem conversas)
    14_448 => 12,  # Email Suporte     │ 14,235 convs → Contato Idiomus
    14_453 => 13,  # Email Teacher Poli│ 10,168 convs → Contato Teacher Poli
    14_638 => 12,  # Suporte extra     │ 1,677 convs → Contato Idiomus
    14_639 => 13   # Extra (emails TP) │ 2,979 convs → Contato Teacher Poli
  }.freeze

  # All agents (active + ex-employees) mapped by Evolvy user_id
  # The import dynamically finds or creates users by email, so this works in any environment
  # (production where users exist, or dev/staging where they need to be created)
  # Emails synced with Evolvy/Chatwoot production on 2025-12-16
  AGENTS = {
    # Active agents
    17_370 => { email: 'betina.ogliari@idiomus.com', name: 'Betina Ogliari' },
    18_090 => { email: 'bruno.araujo@idiomus.com', name: 'Bruno Araujo' },
    18_075 => { email: 'caio.passos@idiomus.com', name: 'Caio Passos' },
    17_313 => { email: 'catherine.mello@idiomus.com', name: 'Catherine' },
    16_396 => { email: 'fabio.gregorio@idiomus.com', name: 'Fabio' },
    17_951 => { email: 'foiato@idiomus.com', name: 'Felipe Foiato' },
    17_861 => { email: 'herison.pereira@idiomus.com', name: 'Herison Pereira' },
    5883 => { email: 'israel@idiomus.com', name: 'Israel' },
    16_887 => { email: 'ivison.freire@idiomus.com', name: 'Ivison' },
    15_861 => { email: 'jorge.frizzo@idiomus.com', name: 'Jorge Frizzo' },
    5986 => { email: 'juliana@idiomus.com', name: 'Juliana Nizer' },
    17_854 => { email: 'laura.moreira@idiomus.com', name: 'Laura' },
    17_297 => { email: 'pablo@idiomus.com', name: 'Pablo Luz' },
    18_077 => { email: 'admin@slever.com.br', name: 'Pedro Lobão' },
    17_840 => { email: 'rachel@idiomus.com', name: 'Rachel' },
    18_106 => { email: 'rafaela.lamim@idiomus.com', name: 'Rafaela Lamim' },
    17_824 => { email: 'vanessa.abreu@idiomus.com', name: 'Vanessa' },
    5995 => { email: 'vinicius@idiomus.com', name: 'Vinicius' },
    # Ex-employees (inactive - for historical data preservation)
    6 => { email: 'adm.sistema@idiomus.com', name: 'ADM (Sistema)', inactive: true, note: 'Bot/Sistema JustSell' },
    5984 => { email: 'jessica@idiomus.com', name: 'Jéssica', inactive: true },
    17_464 => { email: 'tiago.gaspari@idiomus.com', name: 'Tiago Gaspari', inactive: true },
    16_185 => { email: 'suellen.goncalves@idiomus.com', name: 'Suellen', inactive: true },
    15_566 => { email: 'maria.lizandra@idiomus.com', name: 'Lizandra', inactive: true },
    16_826 => { email: 'sandra.postay@idiomus.com', name: 'Sandra', inactive: true },
    16_361 => { email: 'fernando.garcia@idiomus.com', name: 'Fernando', inactive: true },
    17_847 => { email: 'carina.camargo@idiomus.com', name: 'Carina Camargo', inactive: true },
    16_186 => { email: 'camila.teixeira@idiomus.com', name: 'Camila', inactive: true },
    17_463 => { email: 'wallan.david@idiomus.com', name: 'Wallan Peixoto', inactive: true },
    17_404 => { email: 'isadora.magalhaes@idiomus.com', name: 'Isadora Almeida', inactive: true },
    17_468 => { email: 'adriane.rampazzo@idiomus.com', name: 'Adriane Rampazzo', inactive: true },
    1174 => { email: 'guilherme.evolvy@idiomus.com', name: 'Guilherme Suporte', inactive: true, note: 'Suporte Evolvy' },
    17_471 => { email: 'hudson.moreira@idiomus.com', name: 'Hudson Moreira', inactive: true },
    17_507 => { email: 'luan.souza@idiomus.com', name: 'Luan Pereira', inactive: true }
  }.freeze

  TEAM_MAPPING = {
    15_102 => 1, # CS
    12_212 => 2  # Compra
  }.freeze

  def initialize(test_mode: false)
    @account = Account.find(ACCOUNT_ID)
    @contact_mapping = {} # evolvy_contact_id => chatwoot_contact_id
    @inbox_mapping = {}   # evolvy_inbox_id => chatwoot_inbox_id
    @conversation_mapping = {} # evolvy_conversation_id => chatwoot_conversation_id
    @message_mapping = {} # evolvy_message_id => {chatwoot_id:, conversation_id:}
    @agent_mapping = {}   # evolvy_user_id => chatwoot_user_id (built dynamically from AGENTS)
    @attachment_refs = [] # Track attachment references (not imported, just for manifest)
    @stats = Hash.new(0)
    @test_mode = test_mode

    setup_logger

    if @test_mode
      log_info "=== TEST MODE ENABLED ==="
      log_info "  LIMIT_INBOX: #{LIMIT_INBOX || 'all'}"
      log_info "  LIMIT_CONTACTS: #{LIMIT_CONTACTS}"
      log_info "  LIMIT_CONVERSATIONS: #{LIMIT_CONVERSATIONS}"
    end
  end

  def dry_run
    log_info 'Starting dry run...'
    log_info "Dump path: #{DUMP_PATH}"
    log_info "Target account: #{@account.name} (ID: #{ACCOUNT_ID})"

    analyze_contacts
    analyze_inboxes
    analyze_conversations

    print_summary
  end

  def import
    log_info 'Starting Evolvy import (OPTIMIZED - bulk inserts)...'
    log_info "Dump path: #{DUMP_PATH}"
    log_info "Target account: #{@account.name} (ID: #{ACCOUNT_ID})"
    log_info "Cutoff date: #{CUTOFF_DATE || 'none (import all)'}"
    log_info "Target inbox: #{TARGET_INBOX || 'all'}" if TARGET_INBOX
    log_info "Skip contacts: #{SKIP_CONTACTS}" if SKIP_CONTACTS
    log_info "Skip attachments: #{SKIP_ATTACHMENTS}" if SKIP_ATTACHMENTS
    operation_start = Time.current

    # Track created records for diff generation
    @created_records = { contacts: [], conversations: [], messages: [], labels: [] }

    # Setup agent mapping (finds or creates users by email)
    setup_agent_mapping

    # No global transaction - each batch commits independently
    import_labels
    import_inboxes

    if SKIP_CONTACTS
      log_info 'Skipping contact import (SKIP_CONTACTS=true)'
      # Still need to load contact mapping for conversation import
      load_existing_contact_mapping
    else
      import_contacts_bulk
    end

    import_conversations_bulk

    # Generate diff and JSON manifest
    diff_file = generate_import_diff
    manifest_file = generate_import_manifest
    log_operation(@test_mode ? 'test_import' : 'import', 'SUCCESS', {
      mode: @test_mode ? 'TEST' : 'FULL',
      labels_imported: @stats[:labels_imported],
      contacts_imported: @stats[:contacts_imported],
      contacts_skipped: @stats[:contacts_skipped],
      conversations_imported: @stats[:conversations_imported],
      conversations_skipped: @stats[:conversations_skipped] || 0,
      messages_imported: @stats[:messages_imported],
      messages_skipped: @stats[:messages_skipped] || 0,
      attachments_imported: @stats[:attachments_imported],
      diff_file: diff_file,
      manifest_file: manifest_file,
      duration_seconds: (Time.current - operation_start).round(2)
    })

    print_summary
    log_info 'Import completed!'
    log_info "JSON manifest: #{manifest_file}"
  end

  def import_contacts_only
    log_info 'Importing contacts only...'
    operation_start = Time.current
    @created_records = { contacts: [], conversations: [], messages: [], labels: [] }

    ActiveRecord::Base.transaction do
      import_contacts_data
    end

    diff_file = generate_import_diff
    log_operation('import_contacts', 'SUCCESS', {
      contacts_imported: @stats[:contacts_imported],
      contacts_skipped: @stats[:contacts_skipped],
      diff_file: diff_file,
      duration_seconds: (Time.current - operation_start).round(2)
    })

    print_summary
  end

  def import_conversations_only
    log_info 'Importing conversations only...'
    operation_start = Time.current
    @created_records = { contacts: [], conversations: [], messages: [], labels: [] }

    load_existing_mappings
    # Use bulk import (no single transaction) for better error handling
    import_conversations_bulk

    diff_file = generate_import_diff
    log_operation('import_conversations', 'SUCCESS', {
      conversations_imported: @stats[:conversations_imported],
      messages_imported: @stats[:messages_imported],
      diff_file: diff_file,
      duration_seconds: (Time.current - operation_start).round(2)
    })

    print_summary
  end

  def import_specific_conversations(conv_ids)
    log_info "Importing specific conversations: #{conv_ids.join(', ')}"
    operation_start = Time.current
    @created_records = { contacts: [], conversations: [], messages: [], labels: [] }

    load_existing_mappings

    conv_ids.each do |conv_id|
      # Find the conversation file in any inbox folder
      conv_file = Dir.glob(File.join(DUMP_PATH, 'backup', 'inbox_*_conversations', "conversation_#{conv_id}.json")).first

      unless conv_file
        log_error "Conversation #{conv_id} not found in dump"
        next
      end

      # Extract inbox ID from path
      inbox_match = conv_file.match(/inbox_(\d+)_conversations/)
      evolvy_inbox_id = inbox_match[1].to_i

      chatwoot_inbox_id = INBOX_MAPPING[evolvy_inbox_id]
      unless chatwoot_inbox_id
        log_error "No Chatwoot inbox mapping for Evolvy inbox #{evolvy_inbox_id}"
        next
      end

      inbox = Inbox.find(chatwoot_inbox_id)

      begin
        import_single_conversation(conv_file, inbox)
        log_info "✓ Imported conversation #{conv_id}"
      rescue StandardError => e
        log_error "Error importing conversation #{conv_id}: #{e.message}"
      end
    end

    log_info "Specific import complete: #{@stats[:conversations_imported]} conversations, #{@stats[:messages_imported]} messages"
    print_summary
  end

  def import_from_csv_with_logging(csv_file, log_file)
    require 'csv'

    @log_file = File.open(log_file, 'w')
    @log_file.sync = true # Flush immediately

    batch_size = ENV.fetch('BATCH_SIZE', 500).to_i
    skip_attachments = ENV['SKIP_ATTACHMENTS'] == 'true'

    log_to_file "=" * 80
    log_to_file "EVOLVY IMPORT FROM CSV - #{Time.current}"
    log_to_file "=" * 80
    log_to_file "CSV File: #{csv_file}"
    log_to_file "Log File: #{log_file}"
    log_to_file "Batch Size: #{batch_size}"
    log_to_file "Skip Attachments: #{skip_attachments}"
    log_to_file ""

    # Read CSV and filter missing conversations within period
    conversations_to_import = []
    CSV.foreach(csv_file, headers: true) do |row|
      next unless row['status'] == 'nao_importado'
      next unless row['periodo'] == 'dentro_periodo'

      conversations_to_import << {
        evolvy_id: row['evolvy_id'].to_i,
        evolvy_inbox: row['evolvy_inbox'].to_i,
        chatwoot_inbox: row['chatwoot_inbox'].to_i,
        date: row['data']
      }
    end

    total = conversations_to_import.count
    log_to_file "Total conversations to import: #{total}"
    log_to_file ""

    # Group by inbox for reporting and processing
    by_inbox = conversations_to_import.group_by { |c| c[:evolvy_inbox] }
    log_to_file "By Evolvy Inbox:"
    by_inbox.each do |inbox, convs|
      log_to_file "  Inbox #{inbox}: #{convs.count} conversations -> Chatwoot #{INBOX_MAPPING[inbox]}"
    end
    log_to_file ""
    log_to_file "-" * 80
    STDOUT.flush

    log_to_file "[DEBUG] Loading existing mappings..."
    STDOUT.flush
    load_existing_mappings
    log_to_file "[DEBUG] Mappings loaded. Starting import..."
    STDOUT.flush

    @created_records = { contacts: [], conversations: [], messages: [], labels: [] }

    imported = 0
    failed = 0
    skipped = 0
    failures = []
    messages_total = 0

    start_time = Time.current

    # Process by Chatwoot inbox for better batching
    by_inbox.each do |evolvy_inbox_id, conv_list|
      chatwoot_inbox_id = INBOX_MAPPING[evolvy_inbox_id]

      unless chatwoot_inbox_id
        error_msg = "No Chatwoot inbox mapping for Evolvy inbox #{evolvy_inbox_id}"
        log_to_file "[SKIP INBOX] #{error_msg} (#{conv_list.count} conversations)"
        conv_list.each { |c| failures << { id: c[:evolvy_id], inbox: evolvy_inbox_id, error: error_msg } }
        skipped += conv_list.count
        next
      end

      inbox = Inbox.find_by(id: chatwoot_inbox_id)
      unless inbox
        error_msg = "Chatwoot inbox #{chatwoot_inbox_id} not found"
        log_to_file "[SKIP INBOX] #{error_msg} (#{conv_list.count} conversations)"
        conv_list.each { |c| failures << { id: c[:evolvy_id], inbox: evolvy_inbox_id, error: error_msg } }
        skipped += conv_list.count
        next
      end

      log_to_file ""
      log_to_file "[INBOX] Processing Evolvy #{evolvy_inbox_id} -> Chatwoot #{inbox.name} (#{conv_list.count} conversations)"

      # Process in batches for performance
      conv_list.each_slice(batch_size).with_index do |batch, batch_num|
        batch_start = Time.current
        batch_imported = 0
        batch_failed = 0
        batch_messages = 0

        # Pre-load conversation files
        conv_files = batch.map do |conv_info|
          file_path = File.join(DUMP_PATH, 'backup', "inbox_#{evolvy_inbox_id}_conversations", "conversation_#{conv_info[:evolvy_id]}.json")
          File.exist?(file_path) ? { info: conv_info, path: file_path } : nil
        end.compact

        # Pre-fetch existing evolvy_ids to skip duplicates
        batch_evolvy_ids = batch.map { |c| c[:evolvy_id].to_s }
        existing_ids = Conversation.where(account_id: ACCOUNT_ID)
                                   .where("additional_attributes->>'evolvy_id' IN (?)", batch_evolvy_ids)
                                   .pluck(Arel.sql("additional_attributes->>'evolvy_id'"))
                                   .to_set

        conversations_to_insert = []
        conv_metadata = []

        conv_files.each do |item|
          conv_info = item[:info]
          conv_id = conv_info[:evolvy_id]

          # Skip if already imported
          if existing_ids.include?(conv_id.to_s)
            skipped += 1
            next
          end

          begin
            conv_data = JSON.parse(File.read(item[:path]))

            # Find or create contact
            sender_data = conv_data.dig('meta', 'sender')
            contact = find_or_create_contact_for_bulk(sender_data)
            next unless contact

            contact_inbox = find_or_create_contact_inbox_bulk(contact, inbox, sender_data)

            created_time = parse_timestamp(conv_data['created_at'])
            updated_time = parse_timestamp(conv_data['timestamp'] || conv_data['last_activity_at'] || conv_data['created_at'])

            conv_record = {
              account_id: ACCOUNT_ID,
              inbox_id: chatwoot_inbox_id,
              contact_id: contact.id,
              contact_inbox_id: contact_inbox.id,
              status: map_conversation_status_int(conv_data['status']),
              assignee_id: map_agent_id(conv_data.dig('meta', 'assignee', 'id')),
              team_id: map_team_id(conv_data['team_id']),
              additional_attributes: {
                'evolvy_id' => conv_id,
                'evolvy_inbox_id' => conv_data['inbox_id'],
                'evolvy_inbox_name' => conv_data.dig('inbox', 'name'),
                'evolvy_channel_type' => conv_data.dig('meta', 'channel')
              },
              custom_attributes: conv_data['custom_attributes'] || {},
              created_at: created_time,
              updated_at: updated_time,
              last_activity_at: updated_time,
              uuid: SecureRandom.uuid
            }

            conversations_to_insert << conv_record
            conv_metadata << {
              uuid: conv_record[:uuid],
              evolvy_id: conv_id,
              messages: conv_data['messages'] || [],
              labels: conv_data['labels'],
              contact: contact,
              inbox: inbox,
              evolvy_inbox_id: evolvy_inbox_id
            }
          rescue StandardError => e
            failures << { id: conv_id, inbox: evolvy_inbox_id, error: "#{e.class}: #{e.message}", backtrace: e.backtrace.first(3) }
            batch_failed += 1
          end
        end

        # Bulk insert conversations
        if conversations_to_insert.any?
          begin
            Conversation.insert_all(conversations_to_insert)
            batch_imported = conversations_to_insert.count

            # Fetch inserted conversations and import messages
            uuids = conversations_to_insert.map { |c| c[:uuid] }
            inserted_convs = @account.conversations.where(uuid: uuids).index_by(&:uuid)

            conv_metadata.each do |meta|
              conv = inserted_convs[meta[:uuid]]
              next unless conv

              # Import messages
              messages = meta[:messages]
              if messages.any?
                msg_count = import_messages_bulk_for_csv(conv, messages, meta[:contact], meta[:inbox], skip_attachments)
                batch_messages += msg_count
              end

              # Import labels
              if meta[:labels].present?
                conv.add_labels(meta[:labels]) rescue nil
              end
            end
          rescue StandardError => e
            log_to_file "  [BATCH ERROR] #{e.class}: #{e.message}"
            batch_failed += conversations_to_insert.count
            failures << { id: "batch_#{batch_num}", inbox: evolvy_inbox_id, error: e.message, backtrace: e.backtrace.first(5) }
          end
        end

        imported += batch_imported
        failed += batch_failed
        messages_total += batch_messages

        # Progress report
        processed = imported + failed + skipped
        elapsed = Time.current - start_time
        rate = processed / [elapsed, 1].max
        eta_seconds = (total - processed) / [rate, 0.01].max
        eta_min = (eta_seconds / 60).round(1)
        batch_time = (Time.current - batch_start).round(2)

        log_to_file "  Batch #{batch_num + 1}: +#{batch_imported} convs, +#{batch_messages} msgs (#{batch_time}s) | Total: #{processed}/#{total} (#{(processed * 100.0 / total).round(1)}%) | ETA: #{eta_min}min"
      end
    end

    # Final summary
    elapsed_total = Time.current - start_time
    log_to_file ""
    log_to_file "=" * 80
    log_to_file "IMPORT COMPLETE - #{Time.current}"
    log_to_file "=" * 80
    log_to_file "Duration: #{(elapsed_total / 60).round(1)} minutes"
    log_to_file "Rate: #{(total / [elapsed_total, 1].max).round(1)} conversations/second"
    log_to_file ""
    log_to_file "Total processed: #{total}"
    log_to_file "  Imported: #{imported}"
    log_to_file "  Failed: #{failed}"
    log_to_file "  Skipped (duplicates): #{skipped}"
    log_to_file "  Messages imported: #{messages_total}"
    log_to_file ""

    if failures.any?
      log_to_file "=" * 80
      log_to_file "FAILURES DETAIL (#{failures.count} total)"
      log_to_file "=" * 80
      failures.each do |f|
        log_to_file ""
        log_to_file "Conversation ID: #{f[:id]}"
        log_to_file "  Evolvy Inbox: #{f[:inbox]}"
        log_to_file "  Error: #{f[:error]}"
        if f[:backtrace]
          log_to_file "  Backtrace:"
          f[:backtrace].each { |line| log_to_file "    #{line}" }
        end
      end
    end

    log_to_file ""
    log_to_file "Log saved to: #{log_file}"
    @log_file.close

    # Also print summary to console
    puts ""
    puts "=" * 60
    puts "IMPORT COMPLETE"
    puts "=" * 60
    puts "Imported: #{imported} conversations, #{messages_total} messages"
    puts "Failed: #{failed}"
    puts "Skipped: #{skipped}"
    puts "Duration: #{(elapsed_total / 60).round(1)} minutes"
    puts "Log file: #{log_file}"
    puts "=" * 60
  end

  def import_messages_bulk_for_csv(conversation, messages, contact, inbox, skip_attachments = false)
    return 0 if messages.blank?

    # Pre-fetch existing message IDs
    existing_msg_ids = conversation.messages
                                   .where("additional_attributes->>'evolvy_message_id' IS NOT NULL")
                                   .pluck(Arel.sql("additional_attributes->>'evolvy_message_id'"))
                                   .to_set

    messages_to_insert = []

    messages.each do |msg|
      evolvy_msg_id = msg['id'].to_s
      next if existing_msg_ids.include?(evolvy_msg_id)

      sender = determine_message_sender(msg, contact)
      sender_type = sender&.class&.name
      sender_id = sender&.id
      msg_type = msg['message_type'] == 1 ? :outgoing : :incoming

      content = msg['content'] || ''
      content = '[Attachment]' if content.blank? && msg['attachments'].present?

      created_time = parse_timestamp(msg['created_at'])

      messages_to_insert << {
        account_id: ACCOUNT_ID,
        inbox_id: inbox.id,
        conversation_id: conversation.id,
        message_type: Message.message_types[msg_type],
        content: content,
        private: msg['private'] || false,
        sender_type: sender_type,
        sender_id: sender_id,
        content_type: msg['content_type'] || 'text',
        additional_attributes: { 'evolvy_message_id' => evolvy_msg_id },
        created_at: created_time,
        updated_at: created_time
      }
    end

    return 0 if messages_to_insert.empty?

    Message.insert_all(messages_to_insert)
    messages_to_insert.count
  rescue StandardError => e
    log_to_file "    [MSG ERROR] Conv #{conversation.id}: #{e.message}"
    0
  end

  def log_to_file(message)
    puts message
    STDOUT.flush
    @log_file.puts(message) if @log_file
    @log_file.flush if @log_file
  end

  def reimport_messages_for_empty_conversations(log_file_path)
    @log_file = File.open(log_file_path, 'w')
    log_to_file "=" * 60
    log_to_file "REIMPORT MESSAGES FOR EMPTY CONVERSATIONS"
    log_to_file "Started: #{Time.now}"
    log_to_file "=" * 60

    # Find conversations with evolvy_id but no messages using NOT EXISTS (efficient)
    empty_convs = Conversation.unscoped
                              .where("additional_attributes->>'evolvy_id' IS NOT NULL")
                              .where("NOT EXISTS (SELECT 1 FROM messages WHERE messages.conversation_id = conversations.id)")
                              .includes(:inbox, :contact)

    total = empty_convs.count
    log_to_file "Found #{total} conversations without messages"
    log_to_file ""

    success = 0
    failed = 0
    skipped = 0

    empty_convs.find_each.with_index do |conv, idx|
      evolvy_id = conv.additional_attributes['evolvy_id']
      evolvy_inbox = conv.additional_attributes['evolvy_inbox_id']

      unless evolvy_id && evolvy_inbox
        log_to_file "[#{idx + 1}/#{total}] Conv #{conv.id}: Missing evolvy metadata, skipping"
        skipped += 1
        next
      end

      # Find JSON file in dump
      json_path = File.join(DUMP_PATH, 'backup', "inbox_#{evolvy_inbox}_conversations", "conversation_#{evolvy_id}.json")

      unless File.exist?(json_path)
        log_to_file "[#{idx + 1}/#{total}] Conv #{conv.id}: JSON not found at #{json_path}"
        skipped += 1
        next
      end

      begin
        conv_data = JSON.parse(File.read(json_path))
        messages = conv_data['messages'] || []

        if messages.empty?
          log_to_file "[#{idx + 1}/#{total}] Conv #{conv.id}: No messages in JSON"
          skipped += 1
          next
        end

        msg_count = import_messages_bulk_for_csv(conv, messages, conv.contact, conv.inbox, true)

        if msg_count.positive?
          log_to_file "[#{idx + 1}/#{total}] Conv #{conv.id}: Imported #{msg_count} messages"
          success += 1
        else
          log_to_file "[#{idx + 1}/#{total}] Conv #{conv.id}: No new messages imported"
          skipped += 1
        end
      rescue StandardError => e
        log_to_file "[#{idx + 1}/#{total}] Conv #{conv.id}: ERROR - #{e.message}"
        failed += 1
      end

      # Progress every 100
      log_to_file "--- Progress: #{idx + 1}/#{total} (#{success} OK, #{failed} FAIL, #{skipped} SKIP) ---" if ((idx + 1) % 100).zero?
    end

    log_to_file ""
    log_to_file "=" * 60
    log_to_file "SUMMARY"
    log_to_file "=" * 60
    log_to_file "Total processed: #{total}"
    log_to_file "Success: #{success}"
    log_to_file "Failed: #{failed}"
    log_to_file "Skipped: #{skipped}"
    log_to_file "Finished: #{Time.now}"

    @log_file.close
  end

  def validate
    log_info '=' * 60
    log_info 'EVOLVY MIGRATION - DATA INTEGRITY VALIDATION'
    log_info '=' * 60
    log_info "Dump path: #{DUMP_PATH}"
    log_info "Target account: #{@account.name} (ID: #{ACCOUNT_ID})"
    log_info ''

    @errors = []
    @warnings = []
    @checks_passed = 0
    @checks_failed = 0

    validate_contacts_count
    validate_contacts_data_integrity
    validate_conversations_count
    validate_messages_integrity
    validate_timestamps
    validate_labels

    print_validation_summary
  end

  def validate_contacts_count
    log_info '[1/6] Checking contacts count...'

    contacts_file = File.join(DUMP_PATH, 'data', 'evolvy_contacts.json')
    source_data = JSON.parse(File.read(contacts_file))
    source_count = source_data['contacts']&.count || 0

    imported_count = @account.contacts.where("identifier LIKE 'evolvy_%'").count
    from_conversations = @account.contacts.where("custom_attributes->>'created_from_conversation' = 'true'").count
    total_imported = imported_count + from_conversations

    if total_imported >= source_count * 0.95
      log_info "  ✅ Contacts: #{total_imported} imported (source: #{source_count})"
      @checks_passed += 1
    else
      msg = "Contacts: only #{total_imported} imported from #{source_count} (< 95%)"
      log_error "  ❌ #{msg}"
      @errors << msg
      @checks_failed += 1
    end
  end

  def validate_contacts_data_integrity
    log_info '[2/6] Checking contacts data integrity (sample)...'

    # Sample 10 contacts and verify key fields
    sample_contacts = @account.contacts.where("identifier LIKE 'evolvy_%'").limit(10)
    issues = 0

    sample_contacts.each do |contact|
      # Check required fields
      if contact.name.blank? && contact.phone_number.blank? && contact.email.blank?
        issues += 1
        @warnings << "Contact #{contact.id} has no identifiable info"
      end

      # Check evolvy_id in custom_attributes
      unless contact.custom_attributes&.dig('evolvy_id')
        issues += 1
        @warnings << "Contact #{contact.id} missing evolvy_id"
      end
    end

    if issues == 0
      log_info '  ✅ Contact data integrity: OK (sample of 10)'
      @checks_passed += 1
    else
      log_info "  ⚠️  Contact data integrity: #{issues} warnings"
      @checks_passed += 1 # Still pass with warnings
    end
  end

  def validate_conversations_count
    log_info '[3/6] Checking conversations count...'

    # Count source conversations
    conversation_dirs = Dir.glob(File.join(DUMP_PATH, 'backup', 'inbox_*_conversations'))
    source_count = 0
    conversation_dirs.each do |dir|
      source_count += Dir.glob(File.join(dir, 'conversation_*.json')).count
    end

    imported_count = @account.conversations.where("additional_attributes->>'evolvy_id' IS NOT NULL").count

    if imported_count > 0
      percentage = (imported_count.to_f / source_count * 100).round(2)
      log_info "  ✅ Conversations: #{imported_count} imported (source: #{source_count}, #{percentage}%)"
      @checks_passed += 1
    else
      msg = "No conversations imported"
      log_error "  ❌ #{msg}"
      @errors << msg
      @checks_failed += 1
    end
  end

  def validate_messages_integrity
    log_info '[4/6] Checking messages integrity (sample)...'

    # Sample 5 conversations and verify messages
    sample_conversations = @account.conversations
                                   .where("additional_attributes->>'evolvy_id' IS NOT NULL")
                                   .limit(5)

    issues = 0
    total_messages = 0

    sample_conversations.each do |conv|
      evolvy_id = conv.additional_attributes['evolvy_id']

      # Find source file
      source_file = Dir.glob(File.join(DUMP_PATH, 'backup', 'inbox_*_conversations', "conversation_#{evolvy_id}.json")).first

      next unless source_file

      source_data = JSON.parse(File.read(source_file))
      source_messages_count = source_data['messages']&.count || 0
      imported_messages_count = conv.messages.count

      total_messages += imported_messages_count

      if imported_messages_count != source_messages_count
        issues += 1
        @warnings << "Conversation #{evolvy_id}: #{imported_messages_count}/#{source_messages_count} messages"
      end
    end

    if issues == 0
      log_info "  ✅ Messages integrity: OK (#{total_messages} messages in sample)"
      @checks_passed += 1
    else
      log_info "  ⚠️  Messages integrity: #{issues} conversations with message count mismatch"
      @checks_passed += 1 # Pass with warnings
    end
  end

  def validate_timestamps
    log_info '[5/6] Checking timestamps preservation...'

    # Get a sample conversation and verify timestamps are in the past
    sample = @account.conversations
                     .where("additional_attributes->>'evolvy_id' IS NOT NULL")
                     .where('created_at < ?', 1.day.ago)
                     .first

    if sample
      log_info "  ✅ Timestamps preserved (sample: #{sample.created_at})"
      @checks_passed += 1
    else
      # Check if any conversation has old timestamps
      oldest = @account.conversations.order(:created_at).first
      if oldest && oldest.created_at < 1.hour.ago
        log_info "  ✅ Timestamps preserved (oldest: #{oldest.created_at})"
        @checks_passed += 1
      else
        @warnings << "Could not verify timestamp preservation"
        log_info "  ⚠️  Could not verify timestamps (all recent?)"
        @checks_passed += 1
      end
    end
  end

  def validate_labels
    log_info '[6/6] Checking labels...'

    labels_file = File.join(DUMP_PATH, 'data', 'evolvy_labels.json')
    return unless File.exist?(labels_file)

    source_labels = JSON.parse(File.read(labels_file))
    source_count = source_labels.count
    imported_count = @account.labels.count

    if imported_count >= source_count
      log_info "  ✅ Labels: #{imported_count} imported (source: #{source_count})"
      @checks_passed += 1
    else
      msg = "Labels: only #{imported_count}/#{source_count} imported"
      @warnings << msg
      log_info "  ⚠️  #{msg}"
      @checks_passed += 1
    end
  end

  def print_validation_summary
    log_info ''
    log_info '=' * 60
    log_info 'VALIDATION SUMMARY'
    log_info '=' * 60
    log_info "Checks passed: #{@checks_passed}"
    log_info "Checks failed: #{@checks_failed}"
    log_info ''

    if @errors.any?
      log_info 'ERRORS:'
      @errors.each { |e| log_error "  - #{e}" }
    end

    if @warnings.any?
      log_info 'WARNINGS:'
      @warnings.each { |w| log_info "  - #{w}" }
    end

    log_info ''
    if @checks_failed == 0
      log_info '✅ VALIDATION PASSED - Data integrity is acceptable for production'
    else
      log_error '❌ VALIDATION FAILED - Review errors before proceeding to production'
    end
    log_info '=' * 60
  end

  def validate_sender_mapping
    log_info '=' * 80
    log_info 'EVOLVY SENDER MAPPING VALIDATION'
    log_info 'This validates that agent attribution will work correctly in production'
    log_info '=' * 80
    log_info ''

    # Collect all unique user senders from source conversations
    user_senders = collect_user_senders_from_source
    log_info "Found #{user_senders.count} unique agent senders in source data"
    log_info ''

    # Validate each sender against AGENTS
    mapped_count = 0
    unmapped_senders = []
    message_counts = Hash.new(0)

    log_info 'AGENT MAPPING VERIFICATION:'
    log_info '-' * 80
    log_info format('%-12s %-25s %-25s %-25s %-10s', 'Evolvy ID', 'Evolvy Name', 'Evolvy Email', 'Mapped Email', 'Messages')
    log_info '-' * 80

    user_senders.each do |evolvy_id, sender_info|
      agent_data = AGENTS[evolvy_id]
      msg_count = sender_info[:message_count]
      message_counts[evolvy_id] = msg_count

      if agent_data
        mapped_count += 1
        status = '✅'
        log_info format("#{status} %-10s %-25s %-25s %-25s %-10s",
                        evolvy_id,
                        truncate_string(sender_info[:name], 24),
                        truncate_string(sender_info[:email], 24),
                        truncate_string(agent_data[:email], 24),
                        msg_count)
      else
        unmapped_senders << { id: evolvy_id, info: sender_info }
        status = '❌'
        log_info format("#{status} %-10s %-25s %-25s %-25s %-10s",
                        evolvy_id,
                        truncate_string(sender_info[:name], 24),
                        truncate_string(sender_info[:email], 24),
                        'NOT MAPPED',
                        msg_count)
      end
    end

    log_info '-' * 80
    log_info ''

    # Summary
    log_info 'SUMMARY:'
    log_info "  Total unique agent senders: #{user_senders.count}"
    log_info "  Mapped to Chatwoot users:   #{mapped_count}"
    log_info "  Unmapped (will show as bot): #{unmapped_senders.count}"
    log_info ''

    total_agent_messages = message_counts.values.sum
    mapped_messages = message_counts.select { |k, _| AGENTS.key?(k) }.values.sum
    log_info "  Total agent messages: #{total_agent_messages}"
    log_info "  Messages with correct attribution: #{mapped_messages} (#{(mapped_messages.to_f / total_agent_messages * 100).round(2)}%)"
    log_info ''

    # Show outgoing messages without sender (will use fallback agent ADM Sistema)
    if @stats[:outgoing_without_sender] > 0
      log_info "  Outgoing messages without sender: #{@stats[:outgoing_without_sender]} (will use fallback agent 'ADM Sistema')"
      log_info ''
    end

    if unmapped_senders.any?
      log_info 'UNMAPPED SENDERS (need to add to AGENTS constant):'
      unmapped_senders.each do |s|
        log_info "  #{s[:id]} => { email: '...', name: '#{s[:info][:name]}' },  # #{s[:info][:message_count]} messages"
      end
      log_info ''
    end

    # Show sample messages for verification
    show_sample_messages_with_senders

    log_info '=' * 80
    if unmapped_senders.empty?
      log_info '✅ ALL AGENT SENDERS ARE MAPPED - Production import will have correct attribution'
    else
      log_info "⚠️  #{unmapped_senders.count} unmapped senders - Add to AGENTS constant before production import"
    end
    log_info '=' * 80
  end

  def collect_user_senders_from_source
    user_senders = {}
    @stats[:outgoing_without_sender] = 0

    conversation_dirs = Dir.glob(File.join(DUMP_PATH, 'backup', 'inbox_*_conversations'))
    total_files = conversation_dirs.sum { |d| Dir.glob(File.join(d, 'conversation_*.json')).count }

    log_info "Scanning #{total_files} conversation files..."

    conversation_dirs.each do |dir|
      conv_files = Dir.glob(File.join(dir, 'conversation_*.json'))

      conv_files.each do |file|
        conv_data = JSON.parse(File.read(file))
        messages = conv_data['messages'] || []

        messages.each do |msg|
          message_type = msg['message_type'] || 0
          next if message_type == 2 # Skip activity messages

          # Check for sender_type/sender_id fields (Channel::Whatsapp style)
          if msg['sender_type'] == 'User' && msg['sender_id'].present?
            evolvy_id = msg['sender_id']
            sender = msg['sender'] || {}
            user_senders[evolvy_id] ||= {
              name: sender['name'] || 'Unknown',
              email: sender['email'],
              message_count: 0
            }
            user_senders[evolvy_id][:message_count] += 1
            next
          end

          sender = msg['sender']

          # Track outgoing messages without sender (will use fallback)
          if message_type == 1 && (!sender || !sender.is_a?(Hash) || sender.empty? || sender['type'] != 'user')
            @stats[:outgoing_without_sender] += 1 unless sender && sender['type'] == 'user'
          end

          next unless sender && sender['type'] == 'user'

          evolvy_id = sender['id']
          user_senders[evolvy_id] ||= {
            name: sender['name'],
            email: sender['email'],
            message_count: 0
          }
          user_senders[evolvy_id][:message_count] += 1
        end
      rescue JSON::ParserError => e
        log_error "Error parsing #{file}: #{e.message}"
      end
    end

    user_senders
  end

  def show_sample_messages_with_senders
    log_info ''
    log_info 'SAMPLE MESSAGES (first 10 agent messages found):'
    log_info '-' * 80

    conversation_dirs = Dir.glob(File.join(DUMP_PATH, 'backup', 'inbox_*_conversations'))
    samples_shown = 0

    conversation_dirs.each do |dir|
      break if samples_shown >= 10

      conv_files = Dir.glob(File.join(dir, 'conversation_*.json'))

      conv_files.each do |file|
        break if samples_shown >= 10

        conv_data = JSON.parse(File.read(file))
        messages = conv_data['messages'] || []

        messages.each do |msg|
          break if samples_shown >= 10

          sender = msg['sender']
          next unless sender && sender['type'] == 'user'

          evolvy_id = sender['id']
          agent_data = AGENTS[evolvy_id]
          content_preview = truncate_string(msg['content'].to_s.gsub(/\s+/, ' '), 50)

          mapped_info = agent_data ? agent_data[:email] : 'UNMAPPED'
          log_info "  Conv #{conv_data['id']} | Sender: #{sender['name']} (Evolvy #{evolvy_id} → #{mapped_info})"
          log_info "    Message: \"#{content_preview}\""
          log_info ''

          samples_shown += 1
        end
      rescue JSON::ParserError
        next
      end
    end
  end

  def truncate_string(str, max_length)
    return '' if str.nil?
    str.length > max_length ? "#{str[0...max_length - 3]}..." : str
  end

  def create_ex_employee_users
    log_info '=' * 70
    log_info 'CREATING AGENT USERS (active + ex-employees)'
    log_info '=' * 70
    log_info ''
    log_info "Account: #{@account.name} (ID: #{ACCOUNT_ID})"
    log_info "This task finds existing users by email or creates them if needed."
    log_info ''
    operation_start = Time.current
    @created_agent_ids = []

    # Use the unified setup_agent_mapping method
    setup_agent_mapping

    log_info ''
    log_info '=' * 70
    log_info 'SUMMARY'
    log_info '=' * 70
    log_info "  Found existing: #{@stats[:agents_found]}"
    log_info "  Created new:    #{@stats[:agents_created]}"
    log_info "  Total agents:   #{@agent_mapping.count}"
    log_info ''
    log_info '✅ All agent users ready for migration'
    log_info '=' * 70

    # Generate diff and log operation
    diff_file = generate_agents_diff
    log_operation('create_ex_employees', 'SUCCESS', {
      agents_found: @stats[:agents_found],
      agents_created: @stats[:agents_created],
      total_agents: @agent_mapping.count,
      created_user_ids: @created_agent_ids.join(','),
      diff_file: diff_file,
      duration_seconds: (Time.current - operation_start).round(2)
    })
  end

  private

  def setup_logger
    @logger = Logger.new($stdout)
    @logger.formatter = proc do |severity, datetime, _progname, msg|
      "[#{datetime.strftime('%Y-%m-%d %H:%M:%S')}] #{severity}: #{msg}\n"
    end
  end

  def log_info(msg)
    @logger.info(msg)
  end

  def log_error(msg)
    @logger.error(msg)
  end

  # Builds @agent_mapping by finding or creating users by email
  # This works in any environment (production, staging, dev)
  def setup_agent_mapping
    log_info 'Setting up agent mapping (finding/creating users by email)...'

    created = 0
    found = 0
    errors = []

    AGENTS.each do |evolvy_id, agent_data|
      user = User.find_by(email: agent_data[:email])

      if user
        @agent_mapping[evolvy_id] = user.id
        found += 1
      else
        # Create the user
        begin
          # Password with uppercase, lowercase, number, and special char to satisfy Chatwoot validation
          random_password = "#{SecureRandom.hex(16)}Aa1!#"

          user = User.new(
            email: agent_data[:email],
            name: agent_data[:name],
            display_name: agent_data[:name],
            password: random_password,
            password_confirmation: random_password,
            confirmed_at: Time.current,
            custom_attributes: {
              'inactive' => agent_data[:inactive] || false,
              'note' => agent_data[:note],
              'evolvy_migration' => true
            }.compact
          )
          user.skip_confirmation!
          user.save!

          # Add user to account as agent
          AccountUser.create!(
            account: @account,
            user: user,
            role: :agent,
            availability: agent_data[:inactive] ? :offline : :online,
            auto_offline: !agent_data[:inactive]
          )

          @agent_mapping[evolvy_id] = user.id
          @created_agent_ids << user.id if @created_agent_ids
          created += 1
          log_info "  Created: #{agent_data[:name]} (#{agent_data[:email]}) -> ID #{user.id}"
        rescue StandardError => e
          errors << "#{agent_data[:name]}: #{e.message}"
          log_error "  Error creating #{agent_data[:name]}: #{e.message}"
        end
      end
    end

    log_info "Agent mapping complete: #{found} found, #{created} created, #{errors.count} errors"
    @stats[:agents_found] = found
    @stats[:agents_created] = created
  end

  # Analysis methods for dry_run

  def analyze_contacts
    contacts_file = File.join(DUMP_PATH, 'data', 'evolvy_contacts.json')
    return log_error("Contacts file not found: #{contacts_file}") unless File.exist?(contacts_file)

    data = JSON.parse(File.read(contacts_file))
    contacts = data['contacts'] || []

    @stats[:contacts_total] = contacts.count
    @stats[:contacts_with_phone] = contacts.count { |c| c['phone_number'].present? }
    @stats[:contacts_with_email] = contacts.count { |c| c['email'].present? }
    @stats[:contacts_with_labels] = contacts.count { |c| c['labels']&.any? }

    log_info "Contacts: #{@stats[:contacts_total]} total"
  end

  def analyze_inboxes
    inbox_files = Dir.glob(File.join(DUMP_PATH, 'backup', 'inbox_*.json'))
                     .reject { |f| f.include?('_conversations') }

    @stats[:inboxes_total] = inbox_files.count

    inbox_files.each do |file|
      inbox = JSON.parse(File.read(file))
      log_info "  Inbox #{inbox['id']}: #{inbox['name']} (#{inbox['channel_type']})"
    end
  end

  def analyze_conversations
    conversation_dirs = Dir.glob(File.join(DUMP_PATH, 'backup', 'inbox_*_conversations'))
    total_conversations = 0
    total_messages = 0

    conversation_dirs.each do |dir|
      conv_files = Dir.glob(File.join(dir, 'conversation_*.json'))
      total_conversations += conv_files.count

      # Sample a few to estimate messages
      conv_files.first(10).each do |file|
        conv = JSON.parse(File.read(file))
        total_messages += conv['messages']&.count || 0
      end
    end

    @stats[:conversations_total] = total_conversations
    @stats[:messages_estimated] = (total_messages / 10.0 * total_conversations).to_i

    log_info "Conversations: #{total_conversations} total"
    log_info "Messages: ~#{@stats[:messages_estimated]} estimated"
  end

  # Import methods

  def import_labels
    labels_file = File.join(DUMP_PATH, 'data', 'evolvy_labels.json')
    return unless File.exist?(labels_file)

    labels = JSON.parse(File.read(labels_file))
    log_info "Importing #{labels.count} labels..."

    labels.each do |label_data|
      label = @account.labels.find_or_initialize_by(title: label_data['name'])
      was_new = label.new_record?
      label.description = label_data['description']
      label.color = label_data['color']
      label.save!
      @stats[:labels_imported] += 1
      @created_records[:labels] << label.title if was_new && @created_records
    end
  end

  def import_inboxes
    log_info "Using predefined INBOX_MAPPING (#{INBOX_MAPPING.count} entries)..."

    INBOX_MAPPING.each do |evolvy_id, chatwoot_id|
      if chatwoot_id.nil?
        @inbox_mapping[evolvy_id] = nil
        @stats[:inboxes_skipped] += 1
        log_info "  Skip: Evolvy #{evolvy_id} (email - will sync via IMAP)"
        next
      end

      inbox = Inbox.find_by(id: chatwoot_id)
      if inbox
        @inbox_mapping[evolvy_id] = chatwoot_id
        @stats[:inboxes_mapped] += 1
        log_info "  Mapped: Evolvy #{evolvy_id} => #{inbox.name} (ID #{chatwoot_id})"
      else
        log_error "  WARNING: Chatwoot inbox #{chatwoot_id} not found for Evolvy #{evolvy_id}"
        @stats[:inboxes_not_found] += 1
      end
    end

    log_info "  Total: #{@stats[:inboxes_mapped]} mapped, #{@stats[:inboxes_skipped]} skipped, #{@stats[:inboxes_not_found]} not found"
  end

  # ==================== BULK IMPORT METHODS (OPTIMIZED) ====================

  def import_contacts_bulk
    contacts_file = File.join(DUMP_PATH, 'data', 'evolvy_contacts.json')
    return log_error("Contacts file not found: #{contacts_file}") unless File.exist?(contacts_file)

    data = JSON.parse(File.read(contacts_file))
    contacts = data['contacts'] || []

    if @test_mode
      contacts = contacts.first(LIMIT_CONTACTS)
      log_info "TEST MODE: Limited to #{contacts.count} contacts"
    end

    log_info "Importing #{contacts.count} contacts (bulk mode)..."
    total_batches = (contacts.count.to_f / BATCH_SIZE).ceil
    start_time = Time.current

    # Pre-load existing contacts for dedup (with extended timeout for large tables)
    log_info '  Loading existing contacts for deduplication...'
    existing_phones = {}
    existing_emails = {}
    existing_identifiers = {}

    # Temporarily increase statement timeout for large queries
    ActiveRecord::Base.connection.execute("SET statement_timeout = '300s'")
    begin
      existing_phones = @account.contacts.where.not(phone_number: [nil, '']).pluck(:phone_number, :id).to_h
      log_info "    Loaded #{existing_phones.size} phone mappings"
      existing_emails = @account.contacts.where.not(email: [nil, '']).pluck(:email, :id).to_h
      log_info "    Loaded #{existing_emails.size} email mappings"
      existing_identifiers = @account.contacts.where("identifier LIKE 'evolvy_%'").pluck(:identifier, :id).to_h
      log_info "    Loaded #{existing_identifiers.size} evolvy identifier mappings"
    ensure
      # Reset to default timeout
      ActiveRecord::Base.connection.execute("SET statement_timeout = DEFAULT")
    end

    # Pre-load labels
    @label_cache = @account.labels.pluck(:title, :id).to_h

    contacts.each_slice(BATCH_SIZE).with_index do |batch, batch_num|
      batch_start = Time.current
      records_to_insert = []
      labels_to_apply = []
      contact_inboxes_to_create = []

      batch.each do |contact_data|
        evolvy_id = contact_data['id']
        phone = contact_data['phone_number'].presence
        email = contact_data['email'].presence&.downcase
        identifier = "evolvy_#{evolvy_id}"

        # Skip if no identifiable info
        next if phone.blank? && email.blank?

        # Check for existing contact
        existing_id = existing_phones[phone] || existing_emails[email] || existing_identifiers[identifier]
        if existing_id
          @contact_mapping[evolvy_id] = existing_id
          @stats[:contacts_skipped] += 1
          next
        end

        created_at = parse_timestamp(contact_data['created_at'])
        updated_at = parse_timestamp(contact_data['updated_at'])

        records_to_insert << {
          account_id: ACCOUNT_ID,
          name: contact_data['name'].presence || phone || "Contact #{evolvy_id}",
          email: email,
          phone_number: phone,
          identifier: identifier,
          additional_attributes: contact_data['additional_attributes'] || {},
          custom_attributes: (contact_data['custom_attributes'] || {}).merge(
            'evolvy_id' => evolvy_id,
            'evolvy_imported_at' => Time.current.iso8601
          ),
          created_at: created_at,
          updated_at: updated_at,
          last_activity_at: parse_timestamp(contact_data['last_activity_at']) || updated_at
        }

        # Queue labels for later
        if contact_data['labels'].present?
          labels_to_apply << { identifier: identifier, labels: contact_data['labels'] }
        end

        # Queue contact_inboxes for later
        if contact_data['contact_inboxes'].present?
          contact_inboxes_to_create << { identifier: identifier, inboxes: contact_data['contact_inboxes'] }
        end

        # Update dedup caches
        existing_phones[phone] = :pending if phone
        existing_emails[email] = :pending if email
        existing_identifiers[identifier] = :pending
      end

      # Bulk insert contacts
      if records_to_insert.any?
        Contact.insert_all(records_to_insert)
        @stats[:contacts_imported] += records_to_insert.count

        # Fetch inserted IDs and update mapping
        inserted = @account.contacts.where(identifier: records_to_insert.map { |r| r[:identifier] }).pluck(:identifier, :id).to_h
        inserted.each do |identifier, id|
          evolvy_id = identifier.gsub('evolvy_', '').to_i
          @contact_mapping[evolvy_id] = id
          existing_identifiers[identifier] = id
        end

        # Apply labels (batch)
        apply_contact_labels_bulk(labels_to_apply, inserted)

        # Create contact_inboxes (batch)
        create_contact_inboxes_bulk(contact_inboxes_to_create, inserted)
      end

      elapsed = Time.current - batch_start
      total_elapsed = Time.current - start_time
      rate = (@stats[:contacts_imported] + @stats[:contacts_skipped]) / total_elapsed rescue 0
      log_info "  Batch #{batch_num + 1}/#{total_batches}: #{records_to_insert.count} inserted (#{elapsed.round(2)}s, #{rate.round(0)}/s overall)"
    end

    log_info "  Contacts complete: #{@stats[:contacts_imported]} imported, #{@stats[:contacts_skipped]} skipped"
  end

  # Load existing contact mapping for parallel runs (when SKIP_CONTACTS=true)
  def load_existing_contact_mapping
    log_info 'Loading existing contact mapping...'

    # Temporarily increase timeout for large query
    ActiveRecord::Base.connection.execute("SET statement_timeout = '300s'")
    begin
      # Load contacts by evolvy identifier
      @account.contacts.where("identifier LIKE 'evolvy_%'").find_each(batch_size: 5000) do |contact|
        evolvy_id = contact.identifier.gsub('evolvy_', '').to_i
        @contact_mapping[evolvy_id] = contact.id
      end
      log_info "  Loaded #{@contact_mapping.size} contact mappings"
    ensure
      ActiveRecord::Base.connection.execute("SET statement_timeout = DEFAULT")
    end
  end

  def apply_contact_labels_bulk(labels_to_apply, identifier_to_id)
    return if labels_to_apply.empty?

    taggings = []
    labels_to_apply.each do |item|
      contact_id = identifier_to_id[item[:identifier]]
      next unless contact_id

      item[:labels].each do |label_title|
        label_id = @label_cache[label_title]
        next unless label_id

        taggings << {
          tag_id: label_id,
          taggable_type: 'Contact',
          taggable_id: contact_id,
          context: 'labels',
          created_at: Time.current
        }
      end
    end

    ActsAsTaggableOn::Tagging.insert_all(taggings) if taggings.any?
  end

  def create_contact_inboxes_bulk(contact_inboxes_data, identifier_to_id)
    return if contact_inboxes_data.empty?

    records = []
    contact_inboxes_data.each do |item|
      contact_id = identifier_to_id[item[:identifier]]
      next unless contact_id

      item[:inboxes].each do |ci_data|
        evolvy_inbox_id = ci_data.dig('inbox', 'id') || ci_data['inbox_id']
        chatwoot_inbox_id = INBOX_MAPPING[evolvy_inbox_id]
        next unless chatwoot_inbox_id

        records << {
          contact_id: contact_id,
          inbox_id: chatwoot_inbox_id,
          source_id: ci_data['source_id'] || SecureRandom.uuid,
          created_at: Time.current,
          updated_at: Time.current
        }
      end
    end

    ContactInbox.insert_all(records) if records.any?
  rescue StandardError => e
    log_error "Error bulk creating contact_inboxes: #{e.message}"
  end

  def import_conversations_bulk
    conversation_dirs = Dir.glob(File.join(DUMP_PATH, 'backup', 'inbox_*_conversations'))

    if @test_mode && LIMIT_INBOX
      conversation_dirs = conversation_dirs.select { |d| d.include?("inbox_#{LIMIT_INBOX}_") }
      log_info "TEST MODE: Limited to inbox #{LIMIT_INBOX}"
    end

    # Count total files
    total_files = conversation_dirs.sum { |d| Dir.glob(File.join(d, 'conversation_*.json')).count }
    log_info "Total conversations to import: #{total_files}"

    # Suppress broadcasts and callbacks for faster import
    log_info "Suppressing ActionCable broadcasts for faster import..."
    suppress_broadcasts do
      @conversations_imported_count = 0
      start_time = Time.current

      conversation_dirs.each do |dir|
        inbox_id = dir.match(/inbox_(\d+)_conversations/)[1].to_i
        import_conversations_for_inbox_bulk(dir, inbox_id, total_files, start_time)

        break if @test_mode && @conversations_imported_count >= LIMIT_CONVERSATIONS
      end
    end
  end

  # Suppress ActionCable broadcasts and Sidekiq jobs during bulk import
  def suppress_broadcasts
    # Store original callback states
    original_conversation_callbacks = Conversation._commit_callbacks.dup
    original_message_callbacks = Message._commit_callbacks.dup

    begin
      # Skip all after_commit callbacks (which trigger broadcasts)
      Conversation.skip_callback(:commit, :after, raise: false) rescue nil
      Message.skip_callback(:commit, :after, raise: false) rescue nil

      # Disable ActionCable broadcasting
      ActionCable.server.config.disable_request_forgery_protection = true if defined?(ActionCable)

      yield
    ensure
      # Restore callbacks
      Conversation._commit_callbacks = original_conversation_callbacks
      Message._commit_callbacks = original_message_callbacks
    end
  end

  def import_conversations_for_inbox_bulk(dir, evolvy_inbox_id, total_files, start_time)
    chatwoot_inbox_id = INBOX_MAPPING[evolvy_inbox_id]

    if chatwoot_inbox_id.nil?
      if INBOX_MAPPING.key?(evolvy_inbox_id)
        log_info "Skipping inbox #{evolvy_inbox_id} (emails sync via IMAP)"
        @stats[:inboxes_skipped] += 1
        return
      else
        log_error "No mapping for inbox #{evolvy_inbox_id}, skipping"
        @stats[:inboxes_unmapped] += 1
        return
      end
    end

    # Filter by target inbox for parallel imports
    if TARGET_INBOX && TARGET_INBOX != chatwoot_inbox_id
      return # Skip - this inbox handled by another process
    end

    inbox = Inbox.find(chatwoot_inbox_id)
    conv_files = Dir.glob(File.join(dir, 'conversation_*.json')).sort

    if @test_mode
      remaining = LIMIT_CONVERSATIONS - @conversations_imported_count
      conv_files = conv_files.first(remaining)
    end

    log_info "Importing #{conv_files.count} conversations for inbox #{inbox.name} (ID: #{chatwoot_inbox_id})..."

    conv_files.each_slice(500).with_index do |batch, batch_num|
      batch_start = Time.current
      conversations_to_insert = []
      messages_to_insert = []
      conv_labels_to_apply = []
      attachments_to_import = []

      # Pre-fetch existing evolvy_ids in this batch to avoid duplicates
      batch_evolvy_ids = batch.map do |file|
        JSON.parse(File.read(file))['id'].to_s
      rescue StandardError
        nil
      end.compact

      existing_evolvy_ids = Conversation.where(account_id: ACCOUNT_ID)
                                        .where("additional_attributes->>'evolvy_id' IN (?)", batch_evolvy_ids)
                                        .pluck(Arel.sql("additional_attributes->>'evolvy_id'"))
                                        .to_set

      batch.each do |file|
        conv_data = JSON.parse(File.read(file))
        evolvy_conv_id = conv_data['id']

        # Skip if already imported (idempotency)
        if existing_evolvy_ids.include?(evolvy_conv_id.to_s)
          @stats[:conversations_skipped] ||= 0
          @stats[:conversations_skipped] += 1
          next
        end

        # Skip if conversation created after cutoff date (avoid overlap with webhook data)
        if CUTOFF_DATE
          conv_created_at = parse_timestamp(conv_data['created_at'])
          if conv_created_at && conv_created_at.to_date >= CUTOFF_DATE
            @stats[:conversations_cutoff] ||= 0
            @stats[:conversations_cutoff] += 1
            next
          end
        end

        # Find or create contact
        sender_data = conv_data.dig('meta', 'sender')
        contact = find_or_create_contact_for_bulk(sender_data)
        next unless contact

        # Find or create contact_inbox
        contact_inbox = find_or_create_contact_inbox_bulk(contact, inbox, sender_data)

        created_time = parse_timestamp(conv_data['created_at'])
        updated_time = parse_timestamp(conv_data['timestamp'] || conv_data['last_activity_at'] || conv_data['created_at'])

        conversations_to_insert << {
          account_id: ACCOUNT_ID,
          inbox_id: chatwoot_inbox_id,
          contact_id: contact.id,
          contact_inbox_id: contact_inbox.id,
          status: map_conversation_status_int(conv_data['status']),
          assignee_id: map_agent_id(conv_data.dig('meta', 'assignee', 'id')),
          team_id: map_team_id(conv_data['team_id']),
          additional_attributes: {
            'evolvy_id' => evolvy_conv_id,
            'evolvy_inbox_id' => conv_data['inbox_id'],
            'evolvy_inbox_name' => conv_data.dig('inbox', 'name'),
            'evolvy_channel_type' => conv_data.dig('meta', 'channel')
          },
          custom_attributes: conv_data['custom_attributes'] || {},
          created_at: created_time,
          updated_at: updated_time,
          last_activity_at: updated_time,
          uuid: SecureRandom.uuid,
          _evolvy_id: evolvy_conv_id,
          _messages: conv_data['messages'] || [],
          _labels: conv_data['labels'],
          _contact: contact,
          _inbox: inbox,
          _evolvy_inbox_id: evolvy_inbox_id
        }
      rescue StandardError => e
        log_error "Error preparing conversation from #{file}: #{e.message}"
        @stats[:conversations_failed] += 1
      end

      # Bulk insert conversations
      if conversations_to_insert.any?
        # Extract metadata and UUIDs before insert
        uuids = conversations_to_insert.map { |c| c[:uuid] }
        conv_metadata = conversations_to_insert.map do |c|
          {
            uuid: c[:uuid],
            evolvy_id: c.delete(:_evolvy_id),
            messages: c.delete(:_messages),
            labels: c.delete(:_labels),
            contact: c.delete(:_contact),
            inbox: c.delete(:_inbox),
            evolvy_inbox_id: c.delete(:_evolvy_inbox_id)
          }
        end

        Conversation.insert_all(conversations_to_insert)
        @stats[:conversations_imported] += conversations_to_insert.count
        @conversations_imported_count += conversations_to_insert.count

        # Fetch inserted conversations by UUID (reliable, timestamps are preserved from source)
        inserted_convs = @account.conversations
                                 .where(uuid: uuids)
                                 .index_by(&:uuid)

        # Track created conversations for diff
        if @created_records
          inserted_convs.each do |_uuid, conv|
            @created_records[:conversations] << {
              id: conv.id,
              evolvy_id: conv.additional_attributes['evolvy_id'],
              inbox_id: conv.inbox_id
            }
          end
        end

        # Pre-fetch existing message evolvy_ids for ALL conversations in this batch
        # This ensures idempotency if import is re-run or resumed
        conv_ids_in_batch = inserted_convs.values.map(&:id)
        existing_msg_evolvy_ids = Message.where(conversation_id: conv_ids_in_batch)
                                         .where("additional_attributes->>'evolvy_id' IS NOT NULL")
                                         .pluck(Arel.sql("additional_attributes->>'evolvy_id'"))
                                         .to_set

        conv_metadata.each do |meta|
          conversation = inserted_convs[meta[:uuid]]
          next unless conversation

          @conversation_mapping[meta[:evolvy_id]] = conversation.id

          # Prepare messages for bulk insert (with idempotency check)
          prepare_messages_bulk(conversation, meta[:messages], meta[:contact], meta[:inbox], meta[:evolvy_inbox_id], messages_to_insert, attachments_to_import, existing_msg_evolvy_ids)

          # Queue labels
          if meta[:labels].present?
            conv_labels_to_apply << { conversation_id: conversation.id, labels: meta[:labels] }
          end
        end

        # Bulk insert messages
        if messages_to_insert.any?
          # Collect evolvy_ids before insert for mapping lookup
          evolvy_ids_in_batch = messages_to_insert.map { |m| m[:additional_attributes]['evolvy_id'].to_s }

          Message.insert_all(messages_to_insert)
          @stats[:messages_imported] += messages_to_insert.count

          # Query back inserted messages to build evolvy_id -> chatwoot_id mapping
          Message.where(conversation_id: conv_ids_in_batch)
                 .where("additional_attributes->>'evolvy_id' IN (?)", evolvy_ids_in_batch)
                 .pluck(:id, :conversation_id, Arel.sql("additional_attributes->>'evolvy_id'"))
                 .each do |msg_id, conv_id, evolvy_id|
            @message_mapping[evolvy_id] = { chatwoot_id: msg_id, conversation_id: conv_id }
          end
        end

        # Apply conversation labels
        apply_conversation_labels_bulk(conv_labels_to_apply)

        # Handle attachments
        if SKIP_ATTACHMENTS
          # Track attachment references in manifest (don't import)
          attachments_to_import.each do |att_data|
            att_data[:attachments].each do |att|
              @attachment_refs << {
                evolvy_conv_id: att_data[:conv_id],
                evolvy_msg_id: att_data[:msg_evolvy_id],
                file_type: att['file_type'],
                data_url: att['data_url'],
                thumb_url: att['thumb_url']
              }
            end
          end
          @stats[:attachments_tracked] ||= 0
          @stats[:attachments_tracked] += attachments_to_import.sum { |a| a[:attachments].size }
        else
          # Import attachments (sequential - Active Storage limitation)
          import_attachments_sequential(attachments_to_import)
        end
      end

      elapsed = Time.current - batch_start
      total_elapsed = Time.current - start_time
      rate = @conversations_imported_count / total_elapsed rescue 0
      progress = (@conversations_imported_count.to_f / total_files * 100).round(1)
      eta_seconds = (total_files - @conversations_imported_count) / rate rescue 0
      eta_min = (eta_seconds / 60).round(1)

      log_info "  Progress: #{@conversations_imported_count}/#{total_files} (#{progress}%) | #{rate.round(0)} conv/s | ETA: #{eta_min}min | Msgs: #{@stats[:messages_imported]}"
    end
  end

  def find_or_create_contact_for_bulk(sender_data)
    return nil unless sender_data

    evolvy_contact_id = sender_data['id']

    # Check mapping first
    if @contact_mapping[evolvy_contact_id]
      return Contact.find_by(id: @contact_mapping[evolvy_contact_id])
    end

    # Try to find by phone
    if sender_data['phone_number'].present?
      contact = @account.contacts.find_by(phone_number: sender_data['phone_number'])
      if contact
        @contact_mapping[evolvy_contact_id] = contact.id
        return contact
      end
    end

    # Try to find by email
    if sender_data['email'].present?
      contact = @account.contacts.find_by(email: sender_data['email'])
      if contact
        @contact_mapping[evolvy_contact_id] = contact.id
        return contact
      end
    end

    # Try to find by identifier
    identifier = "evolvy_#{evolvy_contact_id}"
    existing = @account.contacts.find_by(identifier: identifier)
    if existing
      @contact_mapping[evolvy_contact_id] = existing.id
      return existing
    end

    # Create contact on-the-fly
    contact = @account.contacts.create!(
      name: sender_data['name'].presence || sender_data['phone_number'] || "Contact #{evolvy_contact_id}",
      email: sender_data['email'].presence,
      phone_number: sender_data['phone_number'].presence,
      identifier: identifier,
      custom_attributes: { 'evolvy_id' => evolvy_contact_id, 'created_from_conversation' => true }
    )
    @contact_mapping[evolvy_contact_id] = contact.id
    @stats[:contacts_created_from_conversations] += 1
    contact
  rescue StandardError => e
    log_error "Error creating contact for #{evolvy_contact_id}: #{e.message}"
    nil
  end

  def find_or_create_contact_inbox_bulk(contact, inbox, sender_data)
    raw_source_id = sender_data&.dig('phone_number').presence
    source_id = sanitize_source_id(raw_source_id, contact)
    ContactInbox.find_or_create_by!(contact: contact, inbox: inbox, source_id: source_id)
  rescue ActiveRecord::RecordInvalid => e
    # If still fails, try with contact.id as fallback
    if e.message.include?('Source')
      ContactInbox.find_or_create_by!(contact: contact, inbox: inbox, source_id: contact.id.to_s)
    else
      raise
    end
  end

  # Sanitize source_id for WhatsApp inboxes (must be digits only, 1-15 chars)
  def sanitize_source_id(raw_source_id, contact)
    if raw_source_id.present?
      # Extract digits only, take last 15
      digits = raw_source_id.to_s.gsub(/\D/, '')
      digits.last(15).presence || contact.id.to_s
    else
      # Fallback: use contact ID
      contact.id.to_s
    end
  end

  def prepare_messages_bulk(conversation, messages_data, contact, inbox, evolvy_inbox_id, messages_array, attachments_array, existing_msg_evolvy_ids = Set.new)
    return if messages_data.blank?

    messages_data.each do |msg_data|
      msg_evolvy_id = msg_data['id'].to_s

      # Skip if message already exists (idempotency)
      if existing_msg_evolvy_ids.include?(msg_evolvy_id)
        @stats[:messages_skipped] ||= 0
        @stats[:messages_skipped] += 1
        next
      end

      sender_type, sender_id = determine_sender_for_bulk(msg_data, contact)

      messages_array << {
        account_id: ACCOUNT_ID,
        inbox_id: inbox.id,
        conversation_id: conversation.id,
        content: msg_data['content'],
        message_type: msg_data['message_type'] || 0,
        content_type: msg_data['content_type'] || 'text',
        private: msg_data['private'] || false,
        status: map_message_status_int(msg_data['status']),
        sender_type: sender_type,
        sender_id: sender_id,
        source_id: msg_data['source_id'],
        content_attributes: msg_data['content_attributes'] || {},
        additional_attributes: (msg_data['additional_attributes'] || {}).merge('evolvy_id' => msg_data['id']),
        created_at: parse_timestamp(msg_data['created_at']),
        updated_at: parse_timestamp(msg_data['created_at'])
      }

      # Queue attachments for later
      if msg_data['attachments'].present?
        attachments_array << {
          evolvy_inbox_id: evolvy_inbox_id,
          conv_id: conversation.additional_attributes['evolvy_id'],
          msg_evolvy_id: msg_data['id'],
          attachments: msg_data['attachments'],
          inbox: inbox
        }
      end
    end
  end

  def determine_sender_for_bulk(msg_data, default_contact)
    message_type = msg_data['message_type'] || 0

    # Activity messages (type=2) never have sender - they are system messages
    return [nil, nil] if message_type == 2

    # Check for separate sender_type/sender_id fields (used by Channel::Whatsapp)
    if msg_data['sender_type'].present? && msg_data['sender_id'].present?
      case msg_data['sender_type']
      when 'Contact'
        return ['Contact', default_contact.id]
      when 'User'
        user_id = map_agent_id(msg_data['sender_id'])
        return user_id ? ['User', user_id] : ['User', fallback_agent_id]
      end
    end

    sender_data = msg_data['sender']

    # No sender data - determine by message type
    unless sender_data.present? && sender_data.is_a?(Hash) && sender_data.any?
      # Incoming messages (type=0) without sender: use contact
      return ['Contact', default_contact.id] if message_type == 0

      # Outgoing messages (type=1,3) without sender: use fallback agent
      return ['User', fallback_agent_id]
    end

    case sender_data['type']
    when 'contact'
      ['Contact', default_contact.id]
    when 'user', 'agent_bot'
      user_id = map_agent_id(sender_data['id'])
      # Use fallback agent for unmapped users instead of contact
      user_id ? ['User', user_id] : ['User', fallback_agent_id]
    else
      # Unknown type - determine by message type
      message_type == 0 ? ['Contact', default_contact.id] : ['User', fallback_agent_id]
    end
  end

  def fallback_agent_id
    # Use ADM (Sistema) as fallback - Evolvy ID 6
    @fallback_agent_id ||= @agent_mapping[6] || find_or_create_fallback_agent
  end

  def find_or_create_fallback_agent
    # Try to find existing system user
    system_user = User.find_by(email: 'adm.sistema@idiomus.com')
    return system_user.id if system_user

    # Create if not exists (should have been created by setup_agent_mapping)
    log_error 'Fallback agent not found. Run evolvy:create_ex_employees first.'
    nil
  end

  def apply_conversation_labels_bulk(conv_labels)
    return if conv_labels.empty?

    taggings = []
    conv_labels.each do |item|
      next if item[:labels].blank?

      item[:labels].each do |label_title|
        label_id = @label_cache[label_title]
        next unless label_id

        taggings << {
          tag_id: label_id,
          taggable_type: 'Conversation',
          taggable_id: item[:conversation_id],
          context: 'labels',
          created_at: Time.current
        }
      end
    end

    ActsAsTaggableOn::Tagging.insert_all(taggings) if taggings.any?
  rescue StandardError => e
    log_error "Error applying conversation labels: #{e.message}"
  end

  def import_attachments_sequential(attachments_data)
    return if attachments_data.empty?

    # Find messages by evolvy_id
    msg_ids = attachments_data.map { |a| a[:msg_evolvy_id] }
    messages_by_evolvy_id = Message.where("additional_attributes->>'evolvy_id' IN (?)", msg_ids.map(&:to_s))
                                   .index_by { |m| m.additional_attributes['evolvy_id'].to_i }

    attachments_data.each do |att_group|
      message = messages_by_evolvy_id[att_group[:msg_evolvy_id]]
      next unless message

      att_group[:attachments].each do |att_data|
        import_single_attachment(message, att_data, att_group[:evolvy_inbox_id], att_group[:conv_id])
      rescue StandardError => e
        log_error "Attachment error #{att_data['id']}: #{e.message}"
        @stats[:attachments_failed] += 1
      end
    end
  end

  def map_conversation_status_int(status)
    case status
    when 'open', 0 then 0
    when 'resolved', 1 then 1
    when 'pending', 2 then 2
    when 'snoozed', 3 then 3
    else 1 # resolved
    end
  end

  def map_message_status_int(status)
    case status
    when 'sent', 0 then 0
    when 'delivered', 'is_delivered', 1 then 1
    when 'read', 'is_read', 2 then 2
    when 'failed', 3 then 3
    else 0 # sent
    end
  end

  # ==================== LEGACY IMPORT METHODS (kept for compatibility) ====================

  def import_contacts_data
    contacts_file = File.join(DUMP_PATH, 'data', 'evolvy_contacts.json')
    return log_error("Contacts file not found: #{contacts_file}") unless File.exist?(contacts_file)

    data = JSON.parse(File.read(contacts_file))
    contacts = data['contacts'] || []

    # Apply limit in test mode
    if @test_mode
      contacts = contacts.first(LIMIT_CONTACTS)
      log_info "TEST MODE: Limited to #{contacts.count} contacts"
    end

    log_info "Importing #{contacts.count} contacts..."

    contacts.each_slice(BATCH_SIZE).with_index do |batch, batch_num|
      log_info "  Processing batch #{batch_num + 1}..."
      import_contacts_batch(batch)
    end
  end

  def import_contacts_batch(batch)
    batch.each do |contact_data|
      import_single_contact(contact_data)
    rescue StandardError => e
      log_error "Error importing contact #{contact_data['id']}: #{e.message}"
      @stats[:contacts_failed] += 1
    end
  end

  def import_single_contact(contact_data)
    evolvy_id = contact_data['id']

    # Skip if no identifiable info
    if contact_data['email'].blank? && contact_data['phone_number'].blank?
      @stats[:contacts_skipped] += 1
      return
    end

    # Find existing by phone or email, or create new
    contact = find_or_build_contact(contact_data)

    # Preserve original timestamps
    contact.class.record_timestamps = false

    contact.assign_attributes(
      name: contact_data['name'].presence || contact_data['phone_number'],
      email: contact_data['email'].presence,
      phone_number: contact_data['phone_number'].presence,
      identifier: "evolvy_#{evolvy_id}",
      additional_attributes: contact_data['additional_attributes'] || {},
      custom_attributes: (contact_data['custom_attributes'] || {}).merge(
        'evolvy_id' => evolvy_id,
        'evolvy_imported_at' => Time.current.iso8601
      ),
      created_at: parse_timestamp(contact_data['created_at']),
      updated_at: parse_timestamp(contact_data['updated_at']),
      last_activity_at: parse_timestamp(contact_data['last_activity_at'])
    )

    contact.save!(validate: false)
    contact.class.record_timestamps = true

    @contact_mapping[evolvy_id] = contact.id
    @stats[:contacts_imported] += 1

    # Import labels for contact
    import_contact_labels(contact, contact_data['labels'])

    # Create contact_inboxes
    import_contact_inboxes(contact, contact_data['contact_inboxes'])
  end

  def find_or_build_contact(contact_data)
    # Try to find by phone number first
    if contact_data['phone_number'].present?
      existing = @account.contacts.find_by(phone_number: contact_data['phone_number'])
      return existing if existing
    end

    # Try to find by email
    if contact_data['email'].present?
      existing = @account.contacts.find_by(email: contact_data['email'].downcase)
      return existing if existing
    end

    # Create new contact
    @account.contacts.new
  end

  def import_contact_labels(contact, labels)
    return if labels.blank?

    labels.each do |label_title|
      label = @account.labels.find_by(title: label_title)
      contact.add_labels([label_title]) if label
    end
  end

  def import_contact_inboxes(contact, contact_inboxes_data)
    return if contact_inboxes_data.blank?

    contact_inboxes_data.each do |ci_data|
      evolvy_inbox_id = ci_data.dig('inbox', 'id') || ci_data['inbox_id']
      chatwoot_inbox_id = @inbox_mapping[evolvy_inbox_id]

      next unless chatwoot_inbox_id

      # Sanitize source_id for WhatsApp (digits only, max 15)
      raw_source_id = ci_data['source_id'] || contact.phone_number
      source_id = sanitize_source_id(raw_source_id, contact)

      ContactInbox.find_or_create_by!(
        contact: contact,
        inbox_id: chatwoot_inbox_id,
        source_id: source_id
      )
    rescue StandardError => e
      log_error "Error creating contact_inbox: #{e.message}"
    end
  end

  def import_conversations_data
    conversation_dirs = Dir.glob(File.join(DUMP_PATH, 'backup', 'inbox_*_conversations'))

    # Filter to specific inbox in test mode
    if @test_mode && LIMIT_INBOX
      conversation_dirs = conversation_dirs.select { |d| d.include?("inbox_#{LIMIT_INBOX}_") }
      log_info "TEST MODE: Limited to inbox #{LIMIT_INBOX}"
    end

    @conversations_imported_count = 0

    conversation_dirs.each do |dir|
      inbox_id = dir.match(/inbox_(\d+)_conversations/)[1].to_i
      import_conversations_for_inbox(dir, inbox_id)

      # Stop if reached limit in test mode
      break if @test_mode && @conversations_imported_count >= LIMIT_CONVERSATIONS
    end
  end

  def import_conversations_for_inbox(dir, evolvy_inbox_id)
    chatwoot_inbox_id = @inbox_mapping[evolvy_inbox_id]
    chatwoot_inbox_id = INBOX_MAPPING[evolvy_inbox_id] if chatwoot_inbox_id.nil? && !@inbox_mapping.key?(evolvy_inbox_id)

    if chatwoot_inbox_id.nil?
      if INBOX_MAPPING.key?(evolvy_inbox_id)
        log_info "Skipping inbox #{evolvy_inbox_id} (mapped to nil - emails sync via IMAP)"
        @stats[:inboxes_skipped] += 1
        return
      else
        log_error "No mapping for inbox #{evolvy_inbox_id}, skipping"
        @stats[:inboxes_unmapped] += 1
        return
      end
    end

    # Filter by target inbox for parallel imports
    if TARGET_INBOX && TARGET_INBOX != chatwoot_inbox_id
      log_info "Skipping inbox #{evolvy_inbox_id} (TARGET_INBOX=#{TARGET_INBOX}, this maps to #{chatwoot_inbox_id})"
      return
    end

    inbox = Inbox.find(chatwoot_inbox_id)
    conv_files = Dir.glob(File.join(dir, 'conversation_*.json'))

    # Apply limit in test mode
    if @test_mode
      remaining = LIMIT_CONVERSATIONS - @conversations_imported_count
      conv_files = conv_files.first(remaining)
      log_info "TEST MODE: Importing #{conv_files.count} conversations (limit: #{LIMIT_CONVERSATIONS})"
    end

    log_info "Importing #{conv_files.count} conversations for inbox #{inbox.name}..."

    conv_files.each_slice(100).with_index do |batch, batch_num|
      log_info "  Batch #{batch_num + 1}..."
      batch.each do |file|
        import_single_conversation(file, inbox)
        @conversations_imported_count += 1
      rescue StandardError => e
        log_error "Error importing conversation from #{file}: #{e.message}"
        @stats[:conversations_failed] += 1
      end
    end
  end

  def import_single_conversation(file, inbox)
    conv_data = JSON.parse(File.read(file))
    evolvy_conv_id = conv_data['id']

    # Find or create contact
    sender_data = conv_data.dig('meta', 'sender')
    contact = find_contact_for_conversation(sender_data)

    return @stats[:conversations_skipped] += 1 unless contact

    # Find or create contact_inbox
    contact_inbox = find_or_create_contact_inbox(contact, inbox, sender_data)

    # Create conversation
    Conversation.record_timestamps = false

    created_time = parse_timestamp(conv_data['created_at'])
    updated_time = parse_timestamp(conv_data['timestamp'] || conv_data['last_activity_at'] || conv_data['created_at'])

    conversation = Conversation.new(
      account: @account,
      inbox: inbox,
      contact: contact,
      contact_inbox: contact_inbox,
      status: map_conversation_status(conv_data['status']),
      assignee_id: map_agent_id(conv_data.dig('meta', 'assignee', 'id')),
      team_id: map_team_id(conv_data['team_id']),
      additional_attributes: {
        'evolvy_id' => evolvy_conv_id,
        'evolvy_inbox_id' => conv_data['inbox_id'],
        'evolvy_inbox_name' => conv_data.dig('inbox', 'name'),
        'evolvy_channel_type' => conv_data.dig('meta', 'channel')
      },
      custom_attributes: conv_data['custom_attributes'] || {},
      created_at: created_time,
      updated_at: updated_time,
      last_activity_at: updated_time
    )

    conversation.save!(validate: false)
    Conversation.record_timestamps = true

    @conversation_mapping[evolvy_conv_id] = conversation.id
    @stats[:conversations_imported] += 1

    # Import messages
    import_messages(conversation, conv_data['messages'], contact, inbox)

    # Import conversation labels
    import_conversation_labels(conversation, conv_data['labels'])
  end

  def find_contact_for_conversation(sender_data)
    return nil unless sender_data

    evolvy_contact_id = sender_data['id']

    # Check mapping first
    if @contact_mapping[evolvy_contact_id]
      return Contact.find_by(id: @contact_mapping[evolvy_contact_id])
    end

    # Try to find by phone
    if sender_data['phone_number'].present?
      contact = @account.contacts.find_by(phone_number: sender_data['phone_number'])
      if contact
        @contact_mapping[evolvy_contact_id] = contact.id
        return contact
      end
    end

    # Try to find by email
    if sender_data['email'].present?
      contact = @account.contacts.find_by(email: sender_data['email'])
      if contact
        @contact_mapping[evolvy_contact_id] = contact.id
        return contact
      end
    end

    # Try to find by identifier
    existing = @account.contacts.find_by(identifier: "evolvy_#{evolvy_contact_id}")
    if existing
      @contact_mapping[evolvy_contact_id] = existing.id
      return existing
    end

    # Create contact on-the-fly if not found
    create_contact_from_sender(sender_data)
  end

  def create_contact_from_sender(sender_data)
    return nil unless sender_data

    evolvy_id = sender_data['id']

    contact = @account.contacts.new(
      name: sender_data['name'].presence || sender_data['phone_number'] || "Contact #{evolvy_id}",
      email: sender_data['email'].presence,
      phone_number: sender_data['phone_number'].presence,
      identifier: "evolvy_#{evolvy_id}",
      custom_attributes: { 'evolvy_id' => evolvy_id, 'created_from_conversation' => true }
    )

    contact.save!(validate: false)
    @contact_mapping[evolvy_id] = contact.id
    @stats[:contacts_created_from_conversations] += 1

    log_info "  Created contact on-the-fly: #{contact.name} (#{contact.phone_number})"
    contact
  end

  def find_or_create_contact_inbox(contact, inbox, sender_data)
    raw_source_id = sender_data&.dig('phone_number')
    source_id = sanitize_source_id(raw_source_id, contact)

    ContactInbox.find_or_create_by!(
      contact: contact,
      inbox: inbox,
      source_id: source_id
    )
  end

  def import_messages(conversation, messages_data, contact, inbox)
    return if messages_data.blank?

    Message.record_timestamps = false

    messages_data.each do |msg_data|
      import_single_message(conversation, msg_data, contact, inbox)
    rescue StandardError => e
      log_error "Error importing message #{msg_data['id']}: #{e.message}"
      @stats[:messages_failed] += 1
    end

    Message.record_timestamps = true
  end

  def import_single_message(conversation, msg_data, default_contact, inbox)
    sender = determine_message_sender(msg_data, default_contact)
    message_type = msg_data['message_type']

    message = Message.new(
      account: @account,
      inbox: inbox,
      conversation: conversation,
      content: msg_data['content'],
      message_type: message_type,
      content_type: msg_data['content_type'] || 'text',
      private: msg_data['private'] || false,
      status: map_message_status(msg_data['status']),
      sender: sender,
      source_id: msg_data['source_id'],
      content_attributes: msg_data['content_attributes'] || {},
      additional_attributes: (msg_data['additional_attributes'] || {}).merge(
        'evolvy_id' => msg_data['id']
      ),
      created_at: parse_timestamp(msg_data['created_at']),
      updated_at: parse_timestamp(msg_data['created_at'])
    )

    message.save!(validate: false)
    @stats[:messages_imported] += 1

    import_message_attachments(message, msg_data, inbox)
  end

  def import_message_attachments(message, msg_data, inbox)
    attachments_data = msg_data['attachments']
    return if attachments_data.blank?

    # Get evolvy_inbox_id from conversation's additional_attributes (stored during import)
    conversation = message.conversation
    evolvy_inbox_id = msg_data.dig('conversation', 'inbox_id') ||
                      conversation.additional_attributes&.dig('evolvy_inbox_id') ||
                      INBOX_MAPPING.key(inbox.id)
    conv_id = msg_data['conversation_id'] || conversation.additional_attributes&.dig('evolvy_id')

    attachments_data.each do |att_data|
      import_single_attachment(message, att_data, evolvy_inbox_id, conv_id)
    rescue StandardError => e
      log_error "Error importing attachment #{att_data['id']}: #{e.message}"
      @stats[:attachments_failed] += 1
    end
  end

  def import_single_attachment(message, att_data, evolvy_inbox_id, conv_id)
    att_id = att_data['id']
    file_type = att_data['file_type'] || 'file'
    mimetype = att_data['mimetype'] || 'application/octet-stream'

    ext = get_attachment_extension(att_data)
    file_path = find_attachment_file(evolvy_inbox_id, conv_id, att_id, ext)

    unless file_path && File.exist?(file_path)
      @stats[:attachments_not_found] += 1
      return
    end

    Attachment.record_timestamps = false

    # Use message timestamp for attachment (preserves original timeline)
    attachment_timestamp = message.created_at || Time.current

    attachment = Attachment.new(
      account: @account,
      message: message,
      file_type: map_attachment_file_type(file_type, mimetype),
      external_url: att_data['data_url'],
      coordinates_lat: att_data.dig('coordinates', 'lat'),
      coordinates_long: att_data.dig('coordinates', 'long'),
      fallback_title: att_data['fallback_title'],
      extension: att_data['extension'] || ext&.delete('.'),
      created_at: attachment_timestamp,
      updated_at: attachment_timestamp
    )

    attachment.file.attach(
      io: File.open(file_path),
      filename: "att_#{att_id}#{ext}",
      content_type: mimetype
    )

    attachment.save!(validate: false)
    Attachment.record_timestamps = true

    @stats[:attachments_imported] += 1
  end

  def find_attachment_file(inbox_id, conv_id, att_id, ext)
    attachments_dir = File.join(DUMP_PATH, 'backup', 'attachments')
    return nil unless Dir.exist?(attachments_dir)

    pattern = File.join(attachments_dir, "inbox_#{inbox_id}", "conv_#{conv_id}", "att_#{att_id}#{ext}")
    files = Dir.glob(pattern)
    return files.first if files.any?

    pattern_any_ext = File.join(attachments_dir, "inbox_#{inbox_id}", "conv_#{conv_id}", "att_#{att_id}.*")
    files = Dir.glob(pattern_any_ext)
    files.first
  end

  def get_attachment_extension(att_data)
    return ".#{att_data['extension']}" if att_data['extension'].present?

    mimetype = att_data['mimetype'] || ''
    mime_map = {
      'audio/mpeg' => '.mp3', 'audio/ogg' => '.ogg', 'audio/opus' => '.oga',
      'audio/wav' => '.wav', 'audio/mp4' => '.m4a',
      'image/jpeg' => '.jpg', 'image/png' => '.png', 'image/gif' => '.gif',
      'image/webp' => '.webp',
      'video/mp4' => '.mp4', 'video/quicktime' => '.mov',
      'application/pdf' => '.pdf', 'text/plain' => '.txt', 'text/csv' => '.csv'
    }
    return mime_map[mimetype] if mime_map[mimetype]

    type_map = { 'audio' => '.mp3', 'image' => '.jpg', 'video' => '.mp4', 'file' => '.bin' }
    type_map[att_data['file_type']] || '.bin'
  end

  # Import attachments for already-imported messages (supports TARGET_INBOX for parallel)
  # Make this method public so it can be called from rake task
  public

  def import_attachments_only
    log_info 'Starting attachment import for existing messages...'
    log_info "Target inbox: #{TARGET_INBOX || 'all'}"
    operation_start = Time.current

    @stats[:attachments_imported] = 0
    @stats[:attachments_failed] = 0
    @stats[:attachments_not_found] = 0
    @stats[:attachments_skipped] = 0
    @stats[:messages_without_evolvy_id] = 0

    conversation_dirs = Dir.glob(File.join(DUMP_PATH, 'backup', 'inbox_*_conversations'))

    total_attachments = 0
    processed_attachments = 0

    conversation_dirs.each do |dir|
      evolvy_inbox_id = dir.match(/inbox_(\d+)_conversations/)[1].to_i
      chatwoot_inbox_id = INBOX_MAPPING[evolvy_inbox_id]

      # Skip unmapped or email inboxes
      next if chatwoot_inbox_id.nil?

      # Filter by target inbox for parallel imports
      next if TARGET_INBOX && TARGET_INBOX != chatwoot_inbox_id

      conv_files = Dir.glob(File.join(dir, 'conversation_*.json'))
      inbox = Inbox.find_by(id: chatwoot_inbox_id)
      log_info "Processing inbox #{inbox&.name || chatwoot_inbox_id} (#{conv_files.count} conversations)..."

      conv_files.each_slice(100) do |batch|
        batch.each do |file|
          process_attachments_for_conversation(file, evolvy_inbox_id)
        end

        processed_attachments += batch.size
        if processed_attachments % 500 == 0
          log_info "  Progress: #{processed_attachments} conversations processed, #{@stats[:attachments_imported]} attachments imported"
        end
      end
    end

    # Log operation
    duration = (Time.current - operation_start).round(2)
    log_info "Attachment import complete!"
    log_info "  Imported: #{@stats[:attachments_imported]}"
    log_info "  Skipped (already exists): #{@stats[:attachments_skipped]}"
    log_info "  Not found: #{@stats[:attachments_not_found]}"
    log_info "  Failed: #{@stats[:attachments_failed]}"
    log_info "  Duration: #{duration}s"

    log_operation('import_attachments', 'SUCCESS', {
      target_inbox: TARGET_INBOX,
      attachments_imported: @stats[:attachments_imported],
      attachments_skipped: @stats[:attachments_skipped],
      attachments_not_found: @stats[:attachments_not_found],
      attachments_failed: @stats[:attachments_failed],
      duration_seconds: duration
    })
  end

  def import_attachments_parallel
    require 'concurrent'

    thread_count = ENV.fetch('THREADS', Concurrent.processor_count).to_i

    # Adjust connection pool size to match threads
    pool_size = thread_count + 5
    ActiveRecord::Base.connection_pool.disconnect!
    config = ActiveRecord::Base.connection_db_config.configuration_hash.dup
    config[:pool] = pool_size
    ActiveRecord::Base.establish_connection(config)
    log_info "Database pool adjusted to #{pool_size} connections"

    log_info "Starting PARALLEL attachment import with #{thread_count} threads..."
    log_info "Target inbox: #{TARGET_INBOX || 'all'}"
    operation_start = Time.current

    # Thread-safe counters
    imported = Concurrent::AtomicFixnum.new(0)
    skipped = Concurrent::AtomicFixnum.new(0)
    not_found = Concurrent::AtomicFixnum.new(0)
    failed = Concurrent::AtomicFixnum.new(0)
    processed_convs = Concurrent::AtomicFixnum.new(0)

    # Build the work queue
    work_queue = Queue.new
    total_items = 0

    log_info "Building work queue..."
    conversation_dirs = Dir.glob(File.join(DUMP_PATH, 'backup', 'inbox_*_conversations'))

    conversation_dirs.each do |dir|
      evolvy_inbox_id = dir.match(/inbox_(\d+)_conversations/)[1].to_i
      chatwoot_inbox_id = INBOX_MAPPING[evolvy_inbox_id]

      next if chatwoot_inbox_id.nil?
      next if TARGET_INBOX && TARGET_INBOX != chatwoot_inbox_id

      conv_files = Dir.glob(File.join(dir, 'conversation_*.json'))

      conv_files.each do |file|
        work_queue << { file: file, evolvy_inbox_id: evolvy_inbox_id }
        total_items += 1
      end
    end

    log_info "Work queue built: #{total_items} conversations to process"

    # Create thread pool
    pool = Concurrent::FixedThreadPool.new(thread_count)
    mutex = Mutex.new

    # Process work queue
    thread_count.times do
      pool.post do
        loop do
          work_item = nil
          begin
            work_item = work_queue.pop(true) # non-blocking
          rescue ThreadError
            break # Queue empty
          end

          next unless work_item

          begin
            result = process_attachments_for_conversation_parallel(
              work_item[:file],
              work_item[:evolvy_inbox_id]
            )

            imported.increment(result[:imported])
            skipped.increment(result[:skipped])
            not_found.increment(result[:not_found])
            failed.increment(result[:failed])
            processed_convs.increment

            if processed_convs.value % 500 == 0
              log_info "  Progress: #{processed_convs.value}/#{total_items} convs, #{imported.value} imported"
            end
          rescue StandardError => e
            mutex.synchronize { log_error "Error processing #{work_item[:file]}: #{e.message}" }
            failed.increment
          end
        end
      end
    end

    # Wait for all work to complete
    pool.shutdown
    pool.wait_for_termination

    # Log results
    duration = (Time.current - operation_start).round(2)
    log_info "Parallel attachment import complete!"
    log_info "  Threads: #{thread_count}"
    log_info "  Conversations: #{processed_convs.value}"
    log_info "  Imported: #{imported.value}"
    log_info "  Skipped (already exists): #{skipped.value}"
    log_info "  Not found: #{not_found.value}"
    log_info "  Failed: #{failed.value}"
    log_info "  Duration: #{duration}s"
    log_info "  Rate: #{(imported.value / duration.to_f).round(2)} att/sec"

    log_operation('import_attachments_parallel', 'SUCCESS', {
      target_inbox: TARGET_INBOX,
      threads: thread_count,
      conversations_processed: processed_convs.value,
      attachments_imported: imported.value,
      attachments_skipped: skipped.value,
      attachments_not_found: not_found.value,
      attachments_failed: failed.value,
      duration_seconds: duration,
      rate_per_second: (imported.value / duration.to_f).round(2)
    })
  end

  def process_attachments_for_conversation_parallel(file, evolvy_inbox_id)
    result = { imported: 0, skipped: 0, not_found: 0, failed: 0 }

    conv_data = JSON.parse(File.read(file))
    evolvy_conv_id = conv_data['id']
    messages_data = conv_data['messages'] || []

    messages_data.each do |msg_data|
      attachments = msg_data['attachments']
      next if attachments.blank?

      msg_evolvy_id = msg_data['id'].to_s

      # Each thread gets its own connection from pool
      message = Message.joins(:conversation)
                       .where(conversations: { account_id: ACCOUNT_ID })
                       .where("messages.additional_attributes->>'evolvy_id' = ?", msg_evolvy_id)
                       .first

      unless message
        next # Don't count as error
      end

      # Check if message already has attachments (idempotency)
      existing_attachment_count = message.attachments.count
      if existing_attachment_count >= attachments.size
        result[:skipped] += attachments.size
        next
      end

      attachments.each do |att_data|
        begin
          att_result = import_single_attachment_parallel(message, att_data, evolvy_inbox_id, evolvy_conv_id)
          result[att_result] += 1
        rescue StandardError => e
          result[:failed] += 1
        end
      end
    end

    result
  rescue JSON::ParserError => e
    result[:failed] += 1
    result
  end

  def import_single_attachment_parallel(message, att_data, evolvy_inbox_id, conv_id)
    att_id = att_data['id']
    file_type = att_data['file_type'] || 'file'
    mimetype = att_data['mimetype'] || 'application/octet-stream'

    ext = get_attachment_extension(att_data)
    file_path = find_attachment_file(evolvy_inbox_id, conv_id, att_id, ext)

    unless file_path && File.exist?(file_path)
      return :not_found
    end

    # Use message timestamp for attachment (preserves original timeline)
    attachment_timestamp = message.created_at || Time.current

    attachment = Attachment.new(
      account: @account,
      message: message,
      file_type: map_attachment_file_type(file_type, mimetype),
      external_url: att_data['data_url'],
      coordinates_lat: att_data.dig('coordinates', 'lat'),
      coordinates_long: att_data.dig('coordinates', 'long'),
      fallback_title: att_data['fallback_title'],
      extension: att_data['extension'] || ext&.delete('.'),
      created_at: attachment_timestamp,
      updated_at: attachment_timestamp
    )

    attachment.file.attach(
      io: File.open(file_path),
      filename: "att_#{att_id}#{ext}",
      content_type: mimetype
    )

    attachment.save!(validate: false)
    :imported
  end

  def process_attachments_for_conversation(file, evolvy_inbox_id)
    conv_data = JSON.parse(File.read(file))
    evolvy_conv_id = conv_data['id']
    messages_data = conv_data['messages'] || []

    messages_data.each do |msg_data|
      attachments = msg_data['attachments']
      next if attachments.blank?

      msg_evolvy_id = msg_data['id'].to_s

      # Find the Chatwoot message by evolvy_id
      message = Message.joins(:conversation)
                       .where(conversations: { account_id: ACCOUNT_ID })
                       .where("messages.additional_attributes->>'evolvy_id' = ?", msg_evolvy_id)
                       .first

      unless message
        @stats[:messages_without_evolvy_id] ||= 0
        @stats[:messages_without_evolvy_id] += 1
        next
      end

      # Check if message already has attachments (idempotency)
      existing_attachment_count = message.attachments.count
      if existing_attachment_count >= attachments.size
        @stats[:attachments_skipped] += attachments.size
        next
      end

      attachments.each do |att_data|
        import_single_attachment_safe(message, att_data, evolvy_inbox_id, evolvy_conv_id)
      end
    end
  rescue JSON::ParserError => e
    log_error "Error parsing #{file}: #{e.message}"
  end

  def import_single_attachment_safe(message, att_data, evolvy_inbox_id, conv_id)
    import_single_attachment(message, att_data, evolvy_inbox_id, conv_id)
  rescue StandardError => e
    log_error "Attachment error #{att_data['id']}: #{e.message}"
    @stats[:attachments_failed] += 1
  end

  def map_attachment_file_type(file_type, mimetype)
    return file_type if %w[image audio video file location contact].include?(file_type)

    case mimetype
    when /^image\// then 'image'
    when /^audio\// then 'audio'
    when /^video\// then 'video'
    else 'file'
    end
  end

  def determine_message_sender(msg_data, default_contact)
    message_type = msg_data['message_type'] || 0

    # Activity messages (type=2) never have sender - they are system messages
    return nil if message_type == 2

    # Check for separate sender_type/sender_id fields (used by Channel::Whatsapp)
    if msg_data['sender_type'].present? && msg_data['sender_id'].present?
      case msg_data['sender_type']
      when 'Contact'
        return default_contact
      when 'User'
        user_id = map_agent_id(msg_data['sender_id'])
        return User.find_by(id: user_id || fallback_agent_id)
      end
    end

    sender_data = msg_data['sender']

    # No sender data - determine by message type
    unless sender_data.present? && sender_data.is_a?(Hash) && sender_data.any?
      # Incoming messages (type=0) without sender: use contact
      return default_contact if message_type == 0

      # Outgoing messages (type=1,3) without sender: use fallback agent
      return User.find_by(id: fallback_agent_id)
    end

    case sender_data['type']
    when 'contact'
      default_contact
    when 'user', 'agent_bot'
      user_id = map_agent_id(sender_data['id'])
      User.find_by(id: user_id || fallback_agent_id)
    else
      # Unknown type - determine by message type
      message_type == 0 ? default_contact : User.find_by(id: fallback_agent_id)
    end
  end

  def import_conversation_labels(conversation, labels)
    return if labels.blank?

    conversation.add_labels(labels)
  rescue StandardError => e
    log_error "Error adding labels to conversation: #{e.message}"
  end

  # Helper methods

  def parse_timestamp(value)
    return Time.current if value.blank?

    case value
    when Integer
      Time.at(value).utc
    when String
      Time.parse(value).utc
    else
      Time.current
    end
  rescue StandardError
    Time.current
  end

  def map_agent_id(evolvy_id)
    return nil if evolvy_id.blank?

    @agent_mapping[evolvy_id.to_i]
  end

  def map_team_id(evolvy_id)
    return nil if evolvy_id.blank?

    TEAM_MAPPING[evolvy_id.to_i]
  end

  def map_conversation_status(status)
    case status
    when 'open', 0 then :open
    when 'resolved', 1 then :resolved
    when 'pending', 2 then :pending
    when 'snoozed', 3 then :snoozed
    else :resolved
    end
  end

  def map_message_status(status)
    case status
    when 'sent', 0 then :sent
    when 'delivered', 'is_delivered', 1 then :delivered
    when 'read', 'is_read', 2 then :read
    when 'failed', 3 then :failed
    else :sent
    end
  end

  def load_existing_mappings
    # Load contact mapping from existing contacts
    @account.contacts.where("identifier LIKE 'evolvy_%'").find_each do |contact|
      evolvy_id = contact.identifier.gsub('evolvy_', '').to_i
      @contact_mapping[evolvy_id] = contact.id
    end

    # Load inbox mapping from existing inboxes
    @account.inboxes.where("name LIKE '[Evolvy]%'").find_each do |inbox|
      # Try to extract evolvy_id from additional_attributes or name pattern
      # This is a simplified version - adjust based on actual data
    end

    log_info "Loaded #{@contact_mapping.count} contact mappings"
  end

  def print_summary
    log_info "\n=== Import Summary ==="
    @stats.each do |key, value|
      log_info "  #{key}: #{value}"
    end
    log_info "=====================\n"
  end

  # ==================== DUPLICATE CLEANUP METHODS ====================
  public

  def show_duplicate_stats
    log_info '=== Duplicate Message Statistics ==='

    # Find all conversations with evolvy_id
    conv_ids = Conversation.where(account_id: ACCOUNT_ID)
                           .where("additional_attributes->>'evolvy_id' IS NOT NULL")
                           .pluck(:id)

    log_info "Conversations with evolvy_id: #{conv_ids.count}"

    # Count total messages with evolvy_id
    total_msgs = Message.where(conversation_id: conv_ids)
                        .where("additional_attributes->>'evolvy_id' IS NOT NULL")
                        .count
    log_info "Total messages with evolvy_id: #{total_msgs}"

    # Count unique evolvy_ids
    unique_count = Message.where(conversation_id: conv_ids)
                          .where("additional_attributes->>'evolvy_id' IS NOT NULL")
                          .select("additional_attributes->>'evolvy_id'")
                          .distinct.count
    log_info "Unique message evolvy_ids: #{unique_count}"

    duplicates = total_msgs - unique_count
    log_info "Duplicate messages: #{duplicates}"
    log_info "Duplication factor: #{(total_msgs.to_f / unique_count).round(2)}x" if unique_count.positive?

    # Show sample duplicates
    log_info "\nSample duplicate evolvy_ids (top 10):"
    dups = Message.unscoped
                  .where(conversation_id: conv_ids)
                  .where("additional_attributes->>'evolvy_id' IS NOT NULL")
                  .group("additional_attributes->>'evolvy_id'")
                  .having('count(*) > 1')
                  .order(Arel.sql('count(*) DESC'))
                  .limit(10)
                  .pluck(Arel.sql("additional_attributes->>'evolvy_id'"), Arel.sql('count(*)'))

    dups.each { |eid, cnt| log_info "  evolvy_id #{eid}: #{cnt} copies" }

    log_info '================================='
  end

  def cleanup_duplicate_messages
    log_info '=== Cleaning Up Duplicate Messages ==='
    operation_start = Time.current

    # Find all conversations with evolvy_id
    conv_ids = Conversation.where(account_id: ACCOUNT_ID)
                           .where("additional_attributes->>'evolvy_id' IS NOT NULL")
                           .pluck(:id)

    log_info "Scanning #{conv_ids.count} conversations with evolvy_id..."

    # Find duplicate evolvy_ids (grouped by evolvy_id with count > 1)
    duplicates_sql = <<-SQL
      SELECT additional_attributes->>'evolvy_id' as evolvy_id, array_agg(id ORDER BY id) as msg_ids
      FROM messages
      WHERE conversation_id IN (#{conv_ids.join(',')})
        AND additional_attributes->>'evolvy_id' IS NOT NULL
      GROUP BY additional_attributes->>'evolvy_id'
      HAVING count(*) > 1
    SQL

    duplicates = ActiveRecord::Base.connection.execute(duplicates_sql).to_a

    if duplicates.empty?
      log_info 'No duplicate messages found!'
      log_operation('cleanup_duplicates', 'NO_DUPLICATES', { conversations_scanned: conv_ids.count })
      return
    end

    log_info "Found #{duplicates.count} evolvy_ids with duplicates"

    # Calculate total messages to delete and prepare audit data
    total_to_delete = 0
    ids_to_delete = []
    audit_data = []

    duplicates.each do |row|
      evolvy_id = row['evolvy_id']
      msg_ids = row['msg_ids'].gsub(/[{}]/, '').split(',').map(&:to_i)
      kept_id = msg_ids.first
      deleted_ids = msg_ids[1..]

      ids_to_delete.concat(deleted_ids)
      total_to_delete += deleted_ids.length

      audit_data << { evolvy_id: evolvy_id, kept: kept_id, deleted: deleted_ids }
    end

    # Generate diff file BEFORE deletion
    diff_file = generate_cleanup_diff(audit_data, conv_ids.count, total_to_delete)
    log_info "Generated audit diff: #{diff_file}"

    log_info "Will delete #{total_to_delete} duplicate messages (keeping oldest by ID)"
    log_info 'Proceeding with deletion in batches of 1000...'

    deleted_count = 0
    ids_to_delete.each_slice(1000) do |batch|
      Message.where(id: batch).delete_all
      deleted_count += batch.count
      log_info "  Deleted #{deleted_count}/#{total_to_delete}"
    end

    # Log operation to OPERATIONS_LOG.md
    operation_data = {
      conversations_scanned: conv_ids.count,
      unique_evolvy_ids_with_duplicates: duplicates.count,
      messages_deleted: deleted_count,
      diff_file: diff_file,
      duration_seconds: (Time.current - operation_start).round(2)
    }
    log_operation('cleanup_duplicates', 'SUCCESS', operation_data)

    log_info "Cleanup complete! Deleted #{deleted_count} duplicate messages."
    log_info '================================='
  end

  def cleanup_duplicate_conversations
    log_info '=== Cleaning Up Duplicate Conversations ==='
    operation_start = Time.current

    # Find duplicate evolvy_ids (grouped by evolvy_id with count > 1)
    duplicates_sql = <<-SQL
      SELECT additional_attributes->>'evolvy_id' as evolvy_id,
             array_agg(id ORDER BY id) as conv_ids
      FROM conversations
      WHERE account_id = #{ACCOUNT_ID}
        AND additional_attributes->>'evolvy_id' IS NOT NULL
      GROUP BY additional_attributes->>'evolvy_id'
      HAVING count(*) > 1
    SQL

    duplicates = ActiveRecord::Base.connection.execute(duplicates_sql).to_a

    if duplicates.empty?
      log_info 'No duplicate conversations found!'
      log_operation('cleanup_duplicate_conversations', 'NO_DUPLICATES', { conversations_scanned: 0 })
      return
    end

    log_info "Found #{duplicates.count} evolvy_ids with duplicate conversations"

    # Prepare audit data and determine which to keep
    audit_data = []
    convs_to_delete = []
    messages_to_reassign = 0

    duplicates.each do |row|
      evolvy_id = row['evolvy_id']
      conv_ids = row['conv_ids'].gsub(/[{}]/, '').split(',').map(&:to_i)

      # Find the conversation with most messages (or oldest if tied)
      convs_with_counts = Conversation.where(id: conv_ids)
                                      .left_joins(:messages)
                                      .group(:id)
                                      .order('COUNT(messages.id) DESC, conversations.id ASC')
                                      .pluck(:id, Arel.sql('COUNT(messages.id)'))

      kept_id = convs_with_counts.first[0]
      kept_msg_count = convs_with_counts.first[1]
      to_delete = conv_ids - [kept_id]

      # Count messages that need reassignment
      msgs_in_deleted = Message.where(conversation_id: to_delete).count
      messages_to_reassign += msgs_in_deleted

      convs_to_delete.concat(to_delete)
      audit_data << {
        evolvy_id: evolvy_id,
        kept: kept_id,
        kept_messages: kept_msg_count,
        deleted: to_delete,
        messages_reassigned: msgs_in_deleted
      }
    end

    # Generate diff file BEFORE changes
    diff_file = generate_conversation_cleanup_diff(audit_data, duplicates.count, convs_to_delete.count, messages_to_reassign)
    log_info "Generated audit diff: #{diff_file}"

    log_info "Will delete #{convs_to_delete.count} duplicate conversations"
    log_info "Will reassign #{messages_to_reassign} messages to kept conversations"

    # Reassign messages from deleted conversations to kept ones
    audit_data.each do |entry|
      next if entry[:deleted].empty?

      # Move messages from deleted conversations to kept one
      Message.where(conversation_id: entry[:deleted]).update_all(conversation_id: entry[:kept])
      log_info "  Reassigned messages from convs #{entry[:deleted].join(',')} to conv #{entry[:kept]}"
    end

    # Delete empty duplicate conversations
    deleted_count = 0
    convs_to_delete.each_slice(100) do |batch|
      # Verify no messages remain before deleting
      remaining_msgs = Message.where(conversation_id: batch).count
      if remaining_msgs > 0
        log_error "ERROR: #{remaining_msgs} messages still in conversations #{batch.join(',')} - skipping deletion"
        next
      end

      Conversation.where(id: batch).destroy_all
      deleted_count += batch.count
      log_info "  Deleted #{deleted_count}/#{convs_to_delete.count} conversations"
    end

    # Log operation
    operation_data = {
      duplicate_evolvy_ids: duplicates.count,
      conversations_deleted: deleted_count,
      messages_reassigned: messages_to_reassign,
      diff_file: diff_file,
      duration_seconds: (Time.current - operation_start).round(2)
    }
    log_operation('cleanup_duplicate_conversations', 'SUCCESS', operation_data)

    log_info "Cleanup complete! Deleted #{deleted_count} duplicate conversations, reassigned #{messages_to_reassign} messages."
    log_info '================================='
  end

  def generate_conversation_cleanup_diff(audit_data, dup_count, convs_to_delete, msgs_to_reassign)
    timestamp = Time.current.strftime('%Y%m%d_%H%M%S')
    diff_path = File.join(DUMP_PATH, 'diffs', "cleanup_duplicate_conversations_#{timestamp}.diff")
    FileUtils.mkdir_p(File.dirname(diff_path))

    File.open(diff_path, 'w') do |f|
      f.puts "=" * 80
      f.puts "DUPLICATE CONVERSATION CLEANUP - #{Time.current.iso8601}"
      f.puts "=" * 80
      f.puts
      f.puts "Unique evolvy_ids with duplicates: #{dup_count}"
      f.puts "Total conversations to delete: #{convs_to_delete}"
      f.puts "Total messages to reassign: #{msgs_to_reassign}"
      f.puts
      f.puts "Strategy: Keep conversation with most messages, reassign orphaned messages, delete empty duplicates"
      f.puts
      f.puts "-" * 80
      f.puts "DETAILED AUDIT"
      f.puts "-" * 80
      f.puts

      audit_data.each do |entry|
        f.puts "evolvy_id #{entry[:evolvy_id]}:"
        f.puts "  kept: conv #{entry[:kept]} (#{entry[:kept_messages]} messages)"
        f.puts "  deleted: convs #{entry[:deleted].join(', ')}"
        f.puts "  messages reassigned: #{entry[:messages_reassigned]}"
        f.puts
      end

      f.puts "=" * 80
      f.puts "END OF DIFF"
      f.puts "=" * 80
    end

    diff_path
  end

  def generate_cleanup_diff(audit_data, conv_count, total_to_delete)
    timestamp = Time.current.strftime('%Y%m%d_%H%M%S')
    diff_path = File.join(DUMP_PATH, 'diffs', "cleanup_duplicates_#{timestamp}.diff")
    FileUtils.mkdir_p(File.dirname(diff_path))

    File.open(diff_path, 'w') do |f|
      f.puts "=" * 80
      f.puts "DUPLICATE MESSAGE CLEANUP - #{Time.current.iso8601}"
      f.puts "=" * 80
      f.puts
      f.puts "Conversations scanned: #{conv_count}"
      f.puts "Unique evolvy_ids with duplicates: #{audit_data.count}"
      f.puts "Total messages to delete: #{total_to_delete}"
      f.puts
      f.puts "Strategy: Keep oldest message (lowest ID), delete newer duplicates"
      f.puts
      f.puts "-" * 80
      f.puts "DETAILED AUDIT (evolvy_id -> kept_msg_id, [deleted_msg_ids])"
      f.puts "-" * 80
      f.puts

      audit_data.each do |entry|
        f.puts "evolvy_id #{entry[:evolvy_id]}: kept=#{entry[:kept]}, deleted=#{entry[:deleted].join(',')}"
      end

      f.puts
      f.puts "=" * 80
      f.puts "END OF DIFF"
      f.puts "=" * 80
    end

    diff_path
  end

  def generate_import_diff
    timestamp = Time.current.strftime('%Y%m%d_%H%M%S')
    operation_type = @test_mode ? 'test_import' : 'import'
    diff_path = File.join(DUMP_PATH, 'diffs', "#{operation_type}_#{timestamp}.diff")
    FileUtils.mkdir_p(File.dirname(diff_path))

    File.open(diff_path, 'w') do |f|
      f.puts "=" * 80
      f.puts "EVOLVY IMPORT - #{Time.current.iso8601}"
      f.puts "Mode: #{@test_mode ? 'TEST' : 'FULL'}"
      f.puts "=" * 80
      f.puts

      f.puts "## SUMMARY"
      f.puts "-" * 40
      f.puts "Labels imported: #{@stats[:labels_imported]}"
      f.puts "Contacts imported: #{@stats[:contacts_imported]}"
      f.puts "Contacts skipped: #{@stats[:contacts_skipped]}"
      f.puts "Conversations imported: #{@stats[:conversations_imported]}"
      f.puts "Conversations skipped: #{@stats[:conversations_skipped] || 0}"
      f.puts "Messages imported: #{@stats[:messages_imported]}"
      f.puts "Messages skipped: #{@stats[:messages_skipped] || 0}"
      f.puts "Attachments imported: #{@stats[:attachments_imported]}"
      f.puts

      f.puts "## CREATED RECORDS"
      f.puts "-" * 40

      if @created_records[:labels].any?
        f.puts "\n### Labels (#{@created_records[:labels].count})"
        @created_records[:labels].each { |r| f.puts "  - #{r}" }
      end

      if @created_records[:contacts].any?
        f.puts "\n### Contacts (#{@created_records[:contacts].count})"
        @created_records[:contacts].first(100).each { |r| f.puts "  - ID: #{r[:id]}, evolvy_id: #{r[:evolvy_id]}, phone: #{r[:phone]}" }
        f.puts "  ... and #{@created_records[:contacts].count - 100} more" if @created_records[:contacts].count > 100
      end

      if @created_records[:conversations].any?
        f.puts "\n### Conversations (#{@created_records[:conversations].count})"
        @created_records[:conversations].first(100).each { |r| f.puts "  - ID: #{r[:id]}, evolvy_id: #{r[:evolvy_id]}, inbox: #{r[:inbox_id]}" }
        f.puts "  ... and #{@created_records[:conversations].count - 100} more" if @created_records[:conversations].count > 100
      end

      if @created_records[:messages].any?
        f.puts "\n### Messages (#{@created_records[:messages].count})"
        f.puts "  (Message IDs not tracked individually for performance)"
      end

      f.puts
      f.puts "=" * 80
      f.puts "END OF DIFF"
      f.puts "=" * 80
    end

    diff_path
  end

  def generate_import_manifest
    timestamp = Time.current.strftime('%Y%m%d_%H%M%S')
    operation_type = @test_mode ? 'test_import' : 'import'
    manifest_path = File.join(DUMP_PATH, 'diffs', "#{operation_type}_manifest_#{timestamp}.json")

    # Build conversations manifest from @created_records
    conversations_manifest = {}
    @created_records[:conversations].each do |conv|
      conversations_manifest[conv[:evolvy_id].to_s] = {
        chatwoot_id: conv[:id],
        inbox_id: conv[:inbox_id]
      }
    end

    # Build contacts manifest
    contacts_manifest = {}
    @contact_mapping.each do |evolvy_id, chatwoot_id|
      contacts_manifest[evolvy_id.to_s] = chatwoot_id
    end

    manifest = {
      generated_at: Time.current.iso8601,
      mode: @test_mode ? 'TEST' : 'FULL',
      cutoff_date: CUTOFF_DATE&.to_s,
      stats: {
        conversations_imported: @stats[:conversations_imported],
        conversations_skipped: @stats[:conversations_skipped] || 0,
        conversations_cutoff: @stats[:conversations_cutoff] || 0,
        messages_imported: @stats[:messages_imported],
        messages_skipped: @stats[:messages_skipped] || 0,
        contacts_imported: @stats[:contacts_imported],
        contacts_skipped: @stats[:contacts_skipped],
        labels_imported: @stats[:labels_imported],
        attachments_imported: @stats[:attachments_imported],
        attachments_tracked: @stats[:attachments_tracked] || 0
      },
      mappings: {
        conversations: conversations_manifest,
        contacts: contacts_manifest,
        messages: @message_mapping,
        agents: @agent_mapping
      },
      attachments: SKIP_ATTACHMENTS ? @attachment_refs : []
    }

    File.write(manifest_path, JSON.generate(manifest))  # Use JSON.generate for smaller file (no pretty print)
    log_info "Generated import manifest: #{manifest_path} (#{(@message_mapping.size / 1000.0).round(1)}K messages tracked)"
    manifest_path
  end

  def generate_agents_diff
    timestamp = Time.current.strftime('%Y%m%d_%H%M%S')
    diff_path = File.join(DUMP_PATH, 'diffs', "create_ex_employees_#{timestamp}.diff")
    FileUtils.mkdir_p(File.dirname(diff_path))

    File.open(diff_path, 'w') do |f|
      f.puts "=" * 80
      f.puts "CREATE EX-EMPLOYEES - #{Time.current.iso8601}"
      f.puts "=" * 80
      f.puts

      f.puts "## SUMMARY"
      f.puts "-" * 40
      f.puts "Agents found (existing): #{@stats[:agents_found]}"
      f.puts "Agents created (new): #{@stats[:agents_created]}"
      f.puts "Total agents mapped: #{@agent_mapping.count}"
      f.puts

      f.puts "## AGENT MAPPING (Evolvy ID -> Chatwoot User ID)"
      f.puts "-" * 40
      @agent_mapping.each do |evolvy_id, chatwoot_id|
        agent_info = AGENTS[evolvy_id]
        f.puts "  #{evolvy_id} -> #{chatwoot_id} (#{agent_info&.dig(:email) || 'unknown'})"
      end

      if @created_agent_ids.any?
        f.puts
        f.puts "## CREATED USER IDS"
        f.puts "-" * 40
        @created_agent_ids.each { |id| f.puts "  - #{id}" }
      end

      f.puts
      f.puts "=" * 80
      f.puts "END OF DIFF"
      f.puts "=" * 80
    end

    diff_path
  end

  def cleanup_inbox(inbox_id)
    log_info "=== Cleaning Up Inbox #{inbox_id} ==="
    operation_start = Time.current

    inbox = Inbox.find_by(id: inbox_id)
    unless inbox
      log_error "Inbox #{inbox_id} not found!"
      return
    end

    log_info "Inbox: #{inbox.name}"

    # Count what we're about to delete
    conversations = inbox.conversations
    conv_count = conversations.count
    msg_count = Message.joins(:conversation).where(conversations: { inbox_id: inbox_id }).count

    log_info "Found #{conv_count} conversations with #{msg_count} messages"

    if conv_count.zero?
      log_info 'Nothing to delete!'
      log_operation('cleanup_inbox', 'NO_DATA', { inbox_id: inbox_id, inbox_name: inbox.name })
      return
    end

    # Generate diff BEFORE deletion
    diff_file = generate_inbox_cleanup_diff(inbox, conv_count, msg_count)
    log_info "Generated audit diff: #{diff_file}"

    # Delete in batches to avoid memory issues
    log_info 'Deleting messages...'
    deleted_msgs = 0
    Message.joins(:conversation)
           .where(conversations: { inbox_id: inbox_id })
           .in_batches(of: 5000) do |batch|
      batch_count = batch.count
      batch.delete_all
      deleted_msgs += batch_count
      log_info "  Deleted #{deleted_msgs}/#{msg_count} messages"
    end

    log_info 'Deleting conversations...'
    deleted_convs = 0
    conversations.in_batches(of: 1000) do |batch|
      batch_count = batch.count
      batch.delete_all
      deleted_convs += batch_count
      log_info "  Deleted #{deleted_convs}/#{conv_count} conversations"
    end

    # Log operation
    operation_data = {
      inbox_id: inbox_id,
      inbox_name: inbox.name,
      conversations_deleted: deleted_convs,
      messages_deleted: deleted_msgs,
      diff_file: diff_file,
      duration_seconds: (Time.current - operation_start).round(2)
    }
    log_operation('cleanup_inbox', 'SUCCESS', operation_data)

    log_info "Cleanup complete! Deleted #{deleted_convs} conversations and #{deleted_msgs} messages from inbox #{inbox.name}."
    log_info '================================='
  end

  def generate_inbox_cleanup_diff(inbox, conv_count, msg_count)
    timestamp = Time.current.strftime('%Y%m%d_%H%M%S')
    diff_path = File.join(DUMP_PATH, 'diffs', "cleanup_inbox_#{inbox.id}_#{timestamp}.diff")
    FileUtils.mkdir_p(File.dirname(diff_path))

    # Sample some conversations for audit trail
    sample_convs = inbox.conversations.limit(100).pluck(:id, :display_id, :created_at)

    File.open(diff_path, 'w') do |f|
      f.puts '=' * 80
      f.puts "INBOX CLEANUP - #{Time.current.iso8601}"
      f.puts '=' * 80
      f.puts
      f.puts "Inbox ID: #{inbox.id}"
      f.puts "Inbox Name: #{inbox.name}"
      f.puts "Conversations to delete: #{conv_count}"
      f.puts "Messages to delete: #{msg_count}"
      f.puts
      f.puts 'WARNING: This is a destructive operation!'
      f.puts 'All conversations and messages in this inbox will be permanently deleted.'
      f.puts
      f.puts '-' * 80
      f.puts 'SAMPLE CONVERSATIONS (first 100)'
      f.puts '-' * 80
      f.puts

      sample_convs.each do |id, display_id, created_at|
        f.puts "  conv_id=#{id}, display_id=#{display_id}, created=#{created_at}"
      end

      if conv_count > 100
        f.puts
        f.puts "  ... and #{conv_count - 100} more conversations"
      end

      f.puts
      f.puts '=' * 80
      f.puts 'END OF DIFF'
      f.puts '=' * 80
    end

    diff_path
  end

  def cleanup_evolvy_imports
    log_info '=== Cleaning Up Evolvy Imports ==='
    operation_start = Time.current

    # Find all conversations with evolvy_id
    evolvy_conversations = Conversation.where(account_id: ACCOUNT_ID)
                                       .where("additional_attributes->>'evolvy_id' IS NOT NULL")

    conv_count = evolvy_conversations.count
    log_info "Found #{conv_count} Evolvy-imported conversations"

    if conv_count.zero?
      log_info 'Nothing to delete!'
      log_operation('cleanup_evolvy_imports', 'NO_DATA', {})
      return
    end

    # Count messages
    conv_ids = evolvy_conversations.pluck(:id)
    msg_count = Message.where(conversation_id: conv_ids).count
    att_count = Attachment.joins(:message).where(messages: { conversation_id: conv_ids }).count

    log_info "Found #{msg_count} messages and #{att_count} attachments to delete"

    # Generate diff BEFORE deletion
    timestamp = Time.current.strftime('%Y%m%d_%H%M%S')
    diff_path = File.join(DUMP_PATH, 'diffs', "cleanup_evolvy_imports_#{timestamp}.diff")
    FileUtils.mkdir_p(File.dirname(diff_path))

    sample_convs = evolvy_conversations.limit(100).pluck(:id, :display_id, Arel.sql("additional_attributes->>'evolvy_id'"))

    File.open(diff_path, 'w') do |f|
      f.puts '=' * 80
      f.puts "EVOLVY IMPORTS CLEANUP - #{Time.current.iso8601}"
      f.puts '=' * 80
      f.puts
      f.puts "Conversations to delete: #{conv_count}"
      f.puts "Messages to delete: #{msg_count}"
      f.puts "Attachments to delete: #{att_count}"
      f.puts
      f.puts '-' * 80
      f.puts 'SAMPLE CONVERSATIONS (first 100)'
      f.puts '-' * 80

      sample_convs.each do |id, display_id, evolvy_id|
        f.puts "  chatwoot_id=#{id}, display_id=#{display_id}, evolvy_id=#{evolvy_id}"
      end

      if conv_count > 100
        f.puts
        f.puts "  ... and #{conv_count - 100} more conversations"
      end
    end

    log_info "Generated audit diff: #{diff_path}"

    # Delete attachments first (foreign key constraint)
    log_info 'Deleting attachments...'
    deleted_atts = Attachment.joins(:message).where(messages: { conversation_id: conv_ids }).delete_all
    log_info "  Deleted #{deleted_atts} attachments"

    # Delete messages
    log_info 'Deleting messages...'
    deleted_msgs = 0
    Message.where(conversation_id: conv_ids).in_batches(of: 5000) do |batch|
      batch_count = batch.count
      batch.delete_all
      deleted_msgs += batch_count
      log_info "  Deleted #{deleted_msgs}/#{msg_count} messages"
    end

    # Delete conversations
    log_info 'Deleting conversations...'
    deleted_convs = 0
    evolvy_conversations.in_batches(of: 1000) do |batch|
      batch_count = batch.count
      batch.delete_all
      deleted_convs += batch_count
      log_info "  Deleted #{deleted_convs}/#{conv_count} conversations"
    end

    # Log operation
    operation_data = {
      conversations_deleted: deleted_convs,
      messages_deleted: deleted_msgs,
      attachments_deleted: deleted_atts,
      diff_file: diff_path,
      duration_seconds: (Time.current - operation_start).round(2)
    }
    log_operation('cleanup_evolvy_imports', 'SUCCESS', operation_data)

    log_info "Cleanup complete! Deleted #{deleted_convs} conversations, #{deleted_msgs} messages, #{deleted_atts} attachments."
    log_info '================================='
  end

  def log_operation(operation_name, status, data = {})
    log_path = File.join(DUMP_PATH, 'OPERATIONS_LOG.md')
    timestamp = Time.current.strftime('%Y-%m-%d %H:%M')

    entry = <<~ENTRY

      ---

      ## #{timestamp} - #{operation_name.titleize} (#{status})

      - **Operator**: Claude (automated)
      - **Database**: #{ENV.fetch('POSTGRES_HOST', 'localhost')} / #{ENV.fetch('POSTGRES_DATABASE', 'chatwoot')}
      - **Command**: `bundle exec rake evolvy:#{operation_name}`
      - **Status**: #{status}

      ### Results
      #{data.map { |k, v| "- **#{k.to_s.titleize}**: #{v}" }.join("\n")}

      ---
    ENTRY

    File.open(log_path, 'a') { |f| f.puts entry }
    log_info "Operation logged to #{log_path}"
  end
end
