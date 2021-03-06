# encoding: utf-8

module SEPA
  PAIN_008_001_02 = 'pain.008.001.02'
  PAIN_008_002_02 = 'pain.008.002.02'
  PAIN_008_003_02 = 'pain.008.003.02'
  PAIN_001_002_03 = 'pain.001.002.03'
  PAIN_001_003_03 = 'pain.001.003.03'

  class Message
    include ActiveModel::Validations

    attr_reader :account, :transactions

    validates_presence_of :transactions
    validate do |record|
      record.errors.add(:account, record.account.errors.full_messages) unless record.account.valid?
    end

    class_attribute :account_class, :transaction_class, :xml_main_tag, :known_schemas

    def initialize(account_options={})
      @transactions = []
      @account = account_class.new(account_options)
    end

    def add_transaction(options)
      transaction = transaction_class.new(options)
      raise ArgumentError.new(transaction.errors.full_messages.join("\n")) unless transaction.valid?
      @transactions << transaction
    end

    # @return [String] xml
    def to_xml(schema_name=self.known_schemas.first)
      raise RuntimeError.new(errors.full_messages.join("\n")) unless valid?
      raise RuntimeError.new("Incompatible with schema #{schema_name}!") unless schema_compatible?(schema_name)

      builder = Builder::XmlMarkup.new indent: 2
      builder.instruct!
      builder.Document(xml_schema(schema_name)) do
        builder.__send__(xml_main_tag) do
          build_group_header(builder)
          build_payment_informations(builder)
        end
      end
    end

    def amount_total(selected_transactions=transactions)
      selected_transactions.inject(0) { |sum, t| sum + t.amount }
    end

    def schema_compatible?(schema_name)
      raise ArgumentError.new("Schema #{schema_name} is unknown!") unless self.known_schemas.include?(schema_name)

      case schema_name
        when PAIN_001_002_03, PAIN_008_002_02, PAIN_008_001_02
          account.bic.present? && transactions.all? { |t| t.schema_compatible?(schema_name) }
        when PAIN_001_003_03, PAIN_008_003_02
          transactions.all? { |t| t.schema_compatible?(schema_name) }
      end
    end

    attr_writer :message_identification # Set unique identifer for the message

    # Unique identifer for the whole message
    def message_identification
      @message_identification ||= "SEPA-KING/#{Time.now.to_i}"
    end

  private
    # @return {Hash<Symbol=>String>} xml schema information used in output xml
    def xml_schema(schema_name)
      { :xmlns                => "urn:iso:std:iso:20022:tech:xsd:#{schema_name}",
        :'xmlns:xsi'          => 'http://www.w3.org/2001/XMLSchema-instance',
        :'xsi:schemaLocation' => "urn:iso:std:iso:20022:tech:xsd:#{schema_name} #{schema_name}.xsd" }
    end

    def build_group_header(builder)
      builder.GrpHdr do
        builder.MsgId(message_identification)
        builder.CreDtTm(Time.now.iso8601)
        builder.NbOfTxs(transactions.length)
        builder.CtrlSum('%.2f' % amount_total)
        builder.InitgPty do
          builder.Nm(account.name)
        end
      end
    end

    # Unique and consecutive identifier (used for the <PmntInf> blocks)
    def payment_information_identification
      @payment_information_counter ||= 0
      @payment_information_counter += 1
      "#{message_identification}/#{@payment_information_counter}"
    end
  end
end
