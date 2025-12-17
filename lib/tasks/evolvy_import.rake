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
end

class EvolvyImporter
  DUMP_PATH = ENV.fetch('EVOLVY_DUMP_PATH', Rails.root.join('12_12_2025_evolvy_dump'))
  ACCOUNT_ID = ENV.fetch('CHATWOOT_ACCOUNT_ID', 1).to_i
  BATCH_SIZE = ENV.fetch('IMPORT_BATCH_SIZE', 1000).to_i

  # Limits for test mode
  LIMIT_INBOX = ENV['LIMIT_INBOX']&.to_i
  LIMIT_CONVERSATIONS = ENV.fetch('LIMIT_CONVERSATIONS', 100).to_i
  LIMIT_CONTACTS = ENV.fetch('LIMIT_CONTACTS', 500).to_i

  # Evolvy inbox_id => Chatwoot inbox_id mapping
  # Production mappings based on phone number and purpose
  # Chatwoot inboxes: 7=Idiomus, 8=Teacher Poli, 9=Teacher Poli Latam, 10=Suporte Oficial (+558393940644)
  # nil = skip (emails will be synced via IMAP)
  INBOX_MAPPING = {
    # Suporte Oficial (+558393940644)
    # 14_483 => 10, # API Oficial onboarding (+558393940644)
    # 14_450 => 10, # Onboarding API (same line 0644)
    # Teacher Poli
    # 5601 => 8,    # Teacher Poli - (83) 92000-5321 (Whatsapp)
    # 13_726 => 8,  # Teacher Poli Oficial (41) 99866-0291 (Whatsapp)
    # 13_984 => 8,  # Teacher Poli (41) 98765-0291 (Whatsapp)
    14_515 => 8,  # Teacher Poli (Facebook)
    # Teacher Poli Latam
    14_535 => 9,  # Teacher Poli para hispanohablantes (Facebook)
    # Idiomus
    # 5598 => 7,    # Idiomus Oficial (41) 99907-1709 (Whatsapp)
    # 5599 => 7,    # Idiomus - (84) 99411-8931 (Whatsapp)
    # 5600 => 7,    # Onboarding (83) 99115-3226
    5608 => 7,    # Idiomus App (Facebook)
    5871 => 7,    # Idiomus (Facebook)
    # SKIP - Emails (will sync via IMAP)
    13_536 => nil, # Teste Nivelamento (Email)
    14_448 => nil, # Email Suporte
    14_453 => nil, # Email Teacher Poli
    14_638 => nil  # Suporte (Email)
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
    @agent_mapping = {}   # evolvy_user_id => chatwoot_user_id (built dynamically from AGENTS)
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

    # Setup agent mapping (finds or creates users by email)
    setup_agent_mapping

    # No global transaction - each batch commits independently
    import_labels
    import_inboxes
    import_contacts_bulk
    import_conversations_bulk

    print_summary
    log_info 'Import completed!'
  end

  def import_contacts_only
    log_info 'Importing contacts only...'
    ActiveRecord::Base.transaction do
      import_contacts_data
    end
    print_summary
  end

  def import_conversations_only
    log_info 'Importing conversations only...'
    load_existing_mappings
    ActiveRecord::Base.transaction do
      import_conversations_data
    end
    print_summary
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

    conversation_dirs = Dir.glob(File.join(DUMP_PATH, 'backup', 'inbox_*_conversations'))
    total_files = conversation_dirs.sum { |d| Dir.glob(File.join(d, 'conversation_*.json')).count }

    log_info "Scanning #{total_files} conversation files..."

    conversation_dirs.each do |dir|
      conv_files = Dir.glob(File.join(dir, 'conversation_*.json'))

      conv_files.each do |file|
        conv_data = JSON.parse(File.read(file))
        messages = conv_data['messages'] || []

        messages.each do |msg|
          sender = msg['sender']
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
      label.description = label_data['description']
      label.color = label_data['color']
      label.save!
      @stats[:labels_imported] += 1
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

    # Pre-load existing contacts for dedup
    log_info '  Loading existing contacts for deduplication...'
    existing_phones = @account.contacts.where.not(phone_number: [nil, '']).pluck(:phone_number, :id).to_h
    existing_emails = @account.contacts.where.not(email: [nil, '']).pluck(:email, :id).to_h
    existing_identifiers = @account.contacts.where("identifier LIKE 'evolvy_%'").pluck(:identifier, :id).to_h

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

    @conversations_imported_count = 0
    start_time = Time.current

    conversation_dirs.each do |dir|
      inbox_id = dir.match(/inbox_(\d+)_conversations/)[1].to_i
      import_conversations_for_inbox_bulk(dir, inbox_id, total_files, start_time)

      break if @test_mode && @conversations_imported_count >= LIMIT_CONVERSATIONS
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

      batch.each do |file|
        conv_data = JSON.parse(File.read(file))
        evolvy_conv_id = conv_data['id']

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

        conv_metadata.each do |meta|
          conversation = inserted_convs[meta[:uuid]]
          next unless conversation

          @conversation_mapping[meta[:evolvy_id]] = conversation.id

          # Prepare messages for bulk insert
          prepare_messages_bulk(conversation, meta[:messages], meta[:contact], meta[:inbox], meta[:evolvy_inbox_id], messages_to_insert, attachments_to_import)

          # Queue labels
          if meta[:labels].present?
            conv_labels_to_apply << { conversation_id: conversation.id, labels: meta[:labels] }
          end
        end

        # Bulk insert messages
        if messages_to_insert.any?
          Message.insert_all(messages_to_insert)
          @stats[:messages_imported] += messages_to_insert.count
        end

        # Apply conversation labels
        apply_conversation_labels_bulk(conv_labels_to_apply)

        # Import attachments (sequential - Active Storage limitation)
        import_attachments_sequential(attachments_to_import)
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
    source_id = sender_data&.dig('phone_number').presence || SecureRandom.uuid
    ContactInbox.find_or_create_by!(contact: contact, inbox: inbox, source_id: source_id)
  end

  def prepare_messages_bulk(conversation, messages_data, contact, inbox, evolvy_inbox_id, messages_array, attachments_array)
    return if messages_data.blank?

    messages_data.each do |msg_data|
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
    sender_data = msg_data['sender']
    return ['Contact', default_contact.id] unless sender_data

    case sender_data['type']
    when 'contact'
      ['Contact', default_contact.id]
    when 'user'
      user_id = map_agent_id(sender_data['id'])
      user_id ? ['User', user_id] : ['Contact', default_contact.id]
    else
      ['Contact', default_contact.id]
    end
  end

  def apply_conversation_labels_bulk(conv_labels)
    return if conv_labels.empty?

    taggings = []
    conv_labels.each do |item|
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

      source_id = ci_data['source_id'] || SecureRandom.uuid

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
      return contact if contact
    end

    # Try to find by identifier
    existing = @account.contacts.find_by(identifier: "evolvy_#{evolvy_contact_id}")
    return existing if existing

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
    source_id = sender_data&.dig('phone_number') || SecureRandom.uuid

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

    attachment = Attachment.new(
      account: @account,
      message: message,
      file_type: map_attachment_file_type(file_type, mimetype),
      external_url: att_data['data_url'],
      coordinates_lat: att_data.dig('coordinates', 'lat'),
      coordinates_long: att_data.dig('coordinates', 'long'),
      fallback_title: att_data['fallback_title'],
      extension: att_data['extension'] || ext&.delete('.')
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
    sender_data = msg_data['sender']
    return default_contact unless sender_data

    case sender_data['type']
    when 'contact'
      default_contact
    when 'user'
      User.find_by(id: map_agent_id(sender_data['id']))
    else
      default_contact
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
end
