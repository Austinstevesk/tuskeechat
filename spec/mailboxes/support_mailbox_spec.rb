require 'rails_helper'

RSpec.describe SupportMailbox, type: :mailbox do
  include ActionMailbox::TestHelper

  describe 'when a chatwoot notification email is received' do
    let(:account) { create(:account) }
    let!(:channel_email) { create(:channel_email, email: 'sojan@chatwoot.com', account: account) }
    let(:notification_mail) { create_inbound_email_from_fixture('notification.eml') }
    let(:described_subject) { described_class.receive notification_mail }
    let(:conversation) { Conversation.where(inbox_id: channel_email.inbox).last }

    it 'shouldnt create a conversation in the channel' do
      described_subject
      expect(conversation.present?).to eq(false)
    end
  end

  describe 'add mail as a new ticket in the email inbox' do
    let(:account) { create(:account) }
    let(:agent) { create(:user, email: 'agent1@example.com', account: account) }
    let!(:channel_email) { create(:channel_email, account: account) }
    let(:support_mail) { create_inbound_email_from_fixture('support.eml') }
    let(:described_subject) { described_class.receive support_mail }
    let(:serialized_attributes) do
      %w[bcc cc content_type date from html_content in_reply_to message_id multipart number_of_attachments subject
         text_content to]
    end
    let(:conversation) { Conversation.where(inbox_id: channel_email.inbox).last }

    before do
      # this email is hardcoded in the support.eml, that's why we are updating this
      channel_email.email = 'care@example.com'
      channel_email.save
    end

    describe 'covers basic ticket creation' do
      before do
        described_subject
      end

      it 'create the conversation in the inbox of the email channel' do
        expect(conversation.inbox.id).to eq(channel_email.inbox.id)
        expect(conversation.additional_attributes['source']).to eq('email')
        expect(conversation.contact.email).to eq(support_mail.mail.from.first)
      end

      it 'create a new contact as the sender of the email' do
        email_sender = Mail::Address.new(support_mail.mail[:from].value).name
        expect(conversation.messages.last.sender.email).to eq(support_mail.mail.from.first)
        expect(conversation.contact.name).to eq(email_sender)
      end

      it 'add the mail content as new message on the conversation' do
        expect(conversation.messages.last.content).to eq("Let's talk about these images:")
      end

      it 'add the attachments' do
        expect(conversation.messages.last.attachments.count).to eq(2)
      end

      it 'have proper content_attributes with details of email' do
        expect(conversation.messages.last.content_attributes[:email].keys).to eq(serialized_attributes)
      end

      it 'set proper content_type' do
        expect(conversation.messages.last.content_type).to eq('incoming_email')
      end
    end

    describe 'Sender without name' do
      let(:support_mail_without_sender_name) { create_inbound_email_from_fixture('support_without_sender_name.eml') }
      let(:described_subject) { described_class.receive support_mail_without_sender_name }

      it 'create a new contact with the email' do
        described_subject
        email_sender = support_mail_without_sender_name.mail.from.first.split('@').first
        expect(conversation.messages.last.sender.email).to eq(support_mail.mail.from.first)
        expect(conversation.contact.name).to eq(email_sender)
      end
    end

    describe 'Sender with upcase mail address' do
      let(:support_mail_without_sender_name) { create_inbound_email_from_fixture('support_without_sender_name.eml') }
      let(:described_subject) { described_class.receive support_mail_without_sender_name }

      it 'create a new inbox with the email case insensitive' do
        described_subject
        expect(conversation.inbox.id).to eq(channel_email.inbox.id)
      end
    end

    describe 'handle inbox contacts' do
      let(:contact) { create(:contact, account: account, email: support_mail.mail.from.first) }
      let(:contact_inbox) { create(:contact_inbox, inbox: channel_email.inbox, contact: contact) }

      it 'does not create new contact if that contact exists in the inbox' do
        # making sure we have a contact already present
        expect(contact_inbox.contact.email).to eq(support_mail.mail.from.first)
        described_subject
        expect(conversation.messages.last.sender.id).to eq(contact.id)
      end
    end

    describe 'group email sender' do
      let(:group_sender_support_mail) { create_inbound_email_from_fixture('group_sender_support.eml') }
      let(:described_subject) { described_class.receive group_sender_support_mail }

      before do
        # this email is hardcoded eml fixture file that's why we are updating this
        channel_email.email = 'support@chatwoot.com'
        channel_email.save
      end

      it 'create new contact with original sender' do
        described_subject
        email_sender = Mail::Address.new(group_sender_support_mail.mail[:from].value).name

        expect(conversation.contact.email).to eq(group_sender_support_mail.mail['X-Original-Sender'].value)
        expect(conversation.contact.name).to eq(email_sender)
      end
    end

    describe 'when mail has in reply to email' do
      let(:reply_mail_without_uuid) { create_inbound_email_from_fixture('reply_mail_without_uuid.eml') }
      let(:described_subject) { described_class.receive reply_mail_without_uuid }
      let(:email_channel) { create(:channel_email, email: 'test@example.com', account: account) }

      before do
        email_channel
        reply_mail_without_uuid.mail['In-Reply-To'] = 'conversation/6bdc3f4d-0bec-4515-a284-5d916fdde489/messages/123'
      end

      it 'create channel with reply to mail' do
        described_subject
        conversation_1 = Conversation.last

        expect(conversation_1.messages.last.content).to eq("Let's talk about these images:")
        expect(conversation_1.additional_attributes['in_reply_to']).to eq('conversation/6bdc3f4d-0bec-4515-a284-5d916fdde489/messages/123')
      end

      it 'append message to email conversation with same in reply to' do
        described_subject
        conversation_1 = Conversation.last

        expect(conversation_1.messages.last.content).to eq("Let's talk about these images:")
        expect(conversation_1.additional_attributes['in_reply_to']).to eq('conversation/6bdc3f4d-0bec-4515-a284-5d916fdde489/messages/123')
        expect(conversation_1.messages.count).to eq(1)

        reply_mail_without_uuid.mail['In-Reply-To'] = 'conversation/6bdc3f4d-0bec-4515-a284-5d916fdde489/messages/123'

        described_class.receive reply_mail_without_uuid

        expect(conversation_1.messages.last.content).to eq("Let's talk about these images:")
        expect(conversation_1.additional_attributes['in_reply_to']).to eq('conversation/6bdc3f4d-0bec-4515-a284-5d916fdde489/messages/123')
        expect(conversation_1.messages.count).to eq(2)
      end
    end

    describe 'Sender with reply_to email address' do
      let(:reply_to_mail) { create_inbound_email_from_fixture('reply_to.eml') }
      let(:email_channel) { create(:channel_email, email: 'test@example.com', account: account) }

      it 'prefer reply-to over from address' do
        email_channel
        described_class.receive reply_to_mail

        conversation_1 = Conversation.last
        email = conversation_1.messages.last.content_attributes['email']

        expect(reply_to_mail.mail['From'].value).to be_present
        expect(conversation_1.messages.last.content).to eq("Let's talk about these images:")
        expect(reply_to_mail.mail['Reply-To'].value).to include(email['from'][0])
        expect(reply_to_mail.mail['Reply-To'].value).to include(conversation_1.contact.email)
        expect(reply_to_mail.mail['From'].value).not_to include(conversation_1.contact.email)
      end
    end
  end
end
