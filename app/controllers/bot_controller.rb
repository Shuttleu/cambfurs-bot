class BotController < ApplicationController

  def send_message(chat_id, message, reply_to_id = nil, reply_markup = nil)
    response = HTTP.get("https://api.telegram.org/bot#{Rails.application.credentials.bot_api!}/sendMessage", params: {chat_id: chat_id, text: message, reply_to_message_id: reply_to_id, reply_markup: reply_markup})
    if response.status.success?
      debug("Message sent: #{message}\nResponse: #{response.body}")
    else
      debug("Error sending message: #{message}\nError: #{response.body}")
    end
  end

  def forward_message(chat_id, origin_chat_id, message_id)
    response = HTTP.get("https://api.telegram.org/bot#{Rails.application.credentials.bot_api!}/forwardMessage", params: {chat_id: chat_id, from_chat_id: origin_chat_id, message_id: message_id})
    if response.status.success?
      debug("Message forwarded\nResponse: #{response.body}")
    else
      debug("Error farwarding message\nError: #{response.body}")
    end
  end

  def request_link(group_id)
    response = HTTP.get("https://api.telegram.org/bot#{Rails.application.credentials.bot_api!}/exportChatInviteLink", params: {chat_id: group_id})
    if response.status.success?
      debug("Link requested:\nResponse: #{response.body}")
      return response.parse["result"]
    else
      debug("Error requesting link:\nError: #{response.body}")
    end
  end

  def remove_user(group_id, user_id)
    response = HTTP.get("https://api.telegram.org/bot#{Rails.application.credentials.bot_api!}/unbanChatMember", params: {chat_id: group_id, user_id: user_id})
    if response.status.success?
      debug("Link rotated:\nResponse: #{response.body}")
    else
      debug("Error rotating link:\nError: #{response.body}")
    end
  end

  def debug(message)
    if Rails.configuration.debug
      print("#{message}\n")
    end
  end

  def start
    debug("New /start from #{params[:message][:chat][:first_name]}")
    send_message(params[:message][:chat][:id], "Howdy #{params[:message][:from][:first_name]}.\nI am the bot for CambFurs admins to help administrate our telegram chats.\nTo get started, please send /help to view a list of all commands.")
  end

  def approve
    debug("Admin approval request from #{params[:message][:from][:first_name]}")
    message = ""
    if params[:message][:from][:id] == Rails.application.credentials.owner_id!
      if params[:message][:reply_to_message].present?
        if !User.where(user_id: params[:message][:reply_to_message][:text]).none?
          user = User.find_by(user_id: params[:message][:reply_to_message][:text])
          user.approved = true
          if user.save
            message = "Approving admin request for #{user.username}."
            send_message(params[:message][:reply_to_message][:text], "You have been approved for admin access! Welcome!")
          else
            message = "Uh oh, something went wrong. Unable to approve admin"
          end
        else
          message = "Admin request not found!"
        end
      else
        message = "You must reply to a message in order to use this command."
      end
    else
      message = "Only my owner can use this command. Sorry! 😢"
    end
    send_message(params[:message][:chat][:id], message)
  end

  def revoke
    debug("Admin revoke request from #{params[:message][:from][:first_name]} for #{params[:message][:reply_to_message].present? ? params[:message][:reply_to_message][:text] : params[:message][:text].delete_prefix("/revoke ")}")
    message = ""
    if params[:message][:from][:id] == Rails.application.credentials.owner_id!
      if params[:message][:reply_to_message].present? || !params[:message][:text].delete_prefix("/revoke ").start_with?("/revoke")
        user_id = params[:message][:reply_to_message].present? ? params[:message][:reply_to_message][:text] : params[:message][:text].delete_prefix("/revoke ")
        if !User.where(user_id: user_id).none?
          user = User.find_by(user_id: user_id)
          user.approved = false
          if user.save
            message = "Revoking admin access for #{user.username}."
            send_message(user_id, "Admin access revoked. If you want to become an admin again, you will have to re-apply")
          else
            message = "Something went wrong, unable to revoke access for #{user.username}."
          end
        else
          message = "Admin not found, unable to revoke access."
        end
      else
        message = "You must reply to a message or specify the user_id in order to use this command."
      end
    else
      message = "Only my owner can use this command. Sorry! 😢"
    end
    send_message(params[:message][:chat][:id], message)
  end

  def apply
    debug("Admin application request from #{params[:message][:from][:first_name]}")
    message = ""
    if User.where(user_id: params[:message][:from][:id], approved: true).none?
      new_user = User.where(user_id: params[:message][:from][:id]).none? ? User.create(username: params[:message][:from][:first_name], user_id: params[:message][:from][:id], approved: false) : User.find_by(user_id: params[:message][:from][:id])
      message = "Admin request sent, please wait for approval."
      send_message(Rails.application.credentials.owner_id!, "New admin request for #{new_user.username}.\nTo approve, please reply to next message with /approve")
      send_message(Rails.application.credentials.owner_id!, "#{new_user.user_id}", nil, "{\"force_reply\": true, \"input_field_placeholder\": \"Approve?\"}")
    else
      message = "You are already an admin, no need to apply again."
    end
    send_message(params[:message][:chat][:id], message)
  end

  def help
    debug("Help message")
    send_message(params[:message][:chat][:id], "This bot is for CambFurs admins to help administrate our Telegram chats.\nInitial available commands:\n\/help - This message\n\/start - Initial welcome message\n\/apply - Send a request to become an admin\n\nOnce approved, you can use the following commands:\n\/list_admins - List all admins and their user_id\n\/list_messages - List of all messages\n\/edit_message - Edit a message which I post\n\/list_blacklist - List all words on the blacklist\n\/add_blacklist - Add a word to the blacklist\n\/delete_blacklist - Remove a word from the blacklist\n\/update_name - Updates your name in the admin list to your current name\n\nOnly my owner can use these commands:\n\/approve - Approve an admin\n\/revoke user_id - Revoke admin access\n\/add_message - add a new message to the system for me to use\n\/delete_message - Delete a message from my memory\n\nThis can only be used in the lobby:\n\/link - Creates a link for a user to join the main group")
  end

  def list_admins
    debug("Admin list request from #{params[:message][:from][:first_name]}")
    message = "List of current admins:"
    if !User.where(user_id: params[:message][:from][:id], approved: true).none?
      User.where(approved: true).each do |user|
        message += "\n#{user.username}: #{user.user_id}"
      end
    else
      message = "Sorry, only admins can use this command."
    end
    send_message(params[:message][:chat][:id], message)
  end

  def list_messages
    debug("Message list request from #{params[:message][:from][:first_name]}")
    message = "List of current messages:"
    if !User.where(user_id: params[:message][:from][:id], approved: true).none?
      Message.all.each do |single_message|
        message += "\n#{single_message.message_id} - #{single_message.message}"
      end
    else
      message = "Sorry, only admins can use this command."
    end
    send_message(params[:message][:chat][:id], message)
  end

  def add_message
    debug("New message request from #{params[:message][:from][:first_name]}")
    message = ""
    force_reply = nil
    if params[:message][:from][:id] == Rails.application.credentials.owner_id!
      message = "Reply to this message with the new message in the format:\nmessage_name - message"
      force_reply = "{\"force_reply\": true, \"input_field_placeholder\": \"name - message\"}"
    else
      message = "Only my owner can use this command. Sorry! 😢"
    end
    send_message(params[:message][:chat][:id], message, nil, force_reply)
  end

  def new_message
    debug("New message response from #{params[:message][:from][:first_name]}, message #{params[:message][:text]}")
    message = ""
    if params[:message][:from][:id] == Rails.application.credentials.owner_id!
      message_parts = params[:message][:text].split(" - ")
      if message_parts.length > 1
        new_message = Message.create(message_id: message_parts[0], message: message_parts[1..-1].join(" - "))
        message = "New message created:\n#{new_message.message_id} - #{new_message.message}"
      else
        message = "Message in incorrect format"
      end
    else
      message = "Only my owner can use this command. Sorry! 😢"
    end
    send_message(params[:message][:chat][:id], message)
  end

  def delete_message
    debug("Delete message request from #{params[:message][:from][:first_name]}")
    message = ""
    force_reply = nil
    if params[:message][:from][:id] == Rails.application.credentials.owner_id!
      message = "Reply to this message with the message_name you'd like to delete."
      force_reply = "{\"force_reply\": true, \"input_field_placeholder\": \"name\"}"
    else
      message = "Only my owner can use this command. Sorry! 😢"
    end
    send_message(params[:message][:chat][:id], message, nil, force_reply)
  end

  def destroy_message
    debug("Delete message response from #{params[:message][:from][:first_name]}, for message #{params[:message][:text]}")
    message = ""
    if params[:message][:from][:id] == Rails.application.credentials.owner_id!
      if !Message.where(message_id: params[:message][:text]).none?
        if Message.find_by(message_id: params[:message][:text]).destroy
          message = "Message deleted!"
        else
          message = "Issue deleting message."
        end
      else
        message = "Unable to find message to delete."
      end
    else
      message = "Only my owner can use this command. Sorry! 😢"
    end
    send_message(params[:message][:chat][:id], message)
  end

  def edit_message
    debug("Edit message request from #{params[:message][:from][:first_name]}")
    message = ""
    force_reply = nil
    if !User.where(user_id: params[:message][:from][:id], approved: true).none?
        message = "Reply to this message with the edited message in the format:\nmessage_name - message"
        force_reply = "{\"force_reply\": true, \"input_field_placeholder\": \"name - new message\"}"
    else
      message = "Sorry, only admins can use this command."
    end
    send_message(params[:message][:chat][:id], message, nil, force_reply)
  end

  def save_message
    debug("Edit message response from #{params[:message][:from][:first_name]}, for message #{params[:message][:text]}")
    message = ""
    if !User.where(user_id: params[:message][:from][:id], approved: true).none?
      message_parts = params[:message][:text].split(" - ")
      if message_parts.length > 1
        if !Message.where(message_id: message_parts[0]).none?
          edited_message = Message.find_by(message_id: message_parts[0])
          edited_message.message = message_parts[1..-1].join(" - ")
          if edited_message.save
            message = "Saved edited message."
          else
            message = "Unable to save new message."
          end
        else
          message = "Unable to find message to edit."
        end
      else
        message = "Incorrect format for edited message."
      end
    else
      message = "Only my owner can use this command. Sorry! 😢"
    end
    send_message(params[:message][:chat][:id], message)
  end

  def list_blacklist
    debug("Blacklist list request from #{params[:message][:from][:first_name]}")
    message = "List of current blacklisted words:"
    if !User.where(user_id: params[:message][:from][:id], approved: true).none?
      Blacklist.all.order(word: :asc).each do |word|
        message += "\n#{word.word}"
      end
    else
      message = "Sorry, only admins can use this command."
    end
    send_message(params[:message][:chat][:id], message)
  end

  def add_blacklist
    debug("New blacklist request from #{params[:message][:from][:first_name]}")
    message = ""
    force_reply = nil
    if !User.where(user_id: params[:message][:from][:id], approved: true).none?
      message = "Reply to this message with the words you would like to add to the blacklist, with each word on a new line"
      force_reply = "{\"force_reply\": true, \"input_field_placeholder\": \"name - message\"}"
    else
      message = "Only admins can use this command. Sorry! 😢"
    end
    send_message(params[:message][:chat][:id], message, nil, force_reply)
  end

  def new_blacklist
    debug("Adding to blacklist request from #{params[:message][:from][:first_name]}")
    message = ""
    added_words = 0
    failed_words = 0
    if !User.where(user_id: params[:message][:from][:id], approved: true).none?
      blacklist_words = params[:message][:text].downcase.split("\n")
      blacklist_words.each do |blacklist_word|
        if Blacklist.where(word: blacklist_word).none?
          Blacklist.create(word: blacklist_word)
          added_words += 1
        else
          failed_words += 1
        end
        message = "#{added_words} words added. #{failed_words} words failed to add."
      end
    else
      message = "Only admins can use this command. Sorry! 😢"
    end
    send_message(params[:message][:chat][:id], message)
  end

  def delete_blacklist
    debug("Remove blacklist request from #{params[:message][:from][:first_name]}")
    message = ""
    force_reply = nil
    if !User.where(user_id: params[:message][:from][:id], approved: true).none?
      message = "Reply to this message with the words you would like to remove from the blacklist, with each word on a new line"
      force_reply = "{\"force_reply\": true, \"input_field_placeholder\": \"name - message\"}"
    else
      message = "Only admins can use this command. Sorry! 😢"
    end
    send_message(params[:message][:chat][:id], message, nil, force_reply)
  end

  def destroy_blacklist
    debug("Destroy blacklist request from #{params[:message][:from][:first_name]}")
    message = ""
    removed_words = 0
    failed_words = 0
    if !User.where(user_id: params[:message][:from][:id], approved: true).none?
      blacklist_words = params[:message][:text].downcase.split("\n")
      blacklist_words.each do |blacklist_word|
        if !Blacklist.where(word: blacklist_word).none?
          Blacklist.find_by(word: blacklist_word).destroy
          removed_words += 1
        else
          failed_words += 1
        end
        message = "#{removed_words} words removed. #{failed_words} words failed to remove."
      end
    else
      message = "Only admins can use this command. Sorry! 😢"
    end
    send_message(params[:message][:chat][:id], message)
  end

  def parse_details(message, username = "")
    message = Message.find_by(message_id: message).message
    message = message.gsub(/{username}/, username)
    return message
  end

  def main_link
    debug("Generating link for main chat for #{params[:message][:from][:username]}")
    send_message(params[:message][:chat][:id], "Please use the following link to join the main chat.\nThis is a single use link and will no longer work once you've joined.\n\n#{request_link(Rails.application.credentials.main_id!)}")
  end

  def check_blacklist
    debug("Checking message for potential blacklisted word")
    Blacklist.all.each do |word|
      if params[:message][:text].downcase.include?(word.word)
        debug("Black listed word found")
        send_message(Rails.application.credentials.admin_id, "Potential blacklisted word found!\n\nWord: #{word.word}\n\nMessage forwarded below.")
        forward_message(Rails.application.credentials.admin_id, params[:message][:chat][:id], params[:message][:message_id])
        return
      end
    end
  end

  def update_name
    debug("update name request for #{params[:message][:from][:first_name]}")
    message = ""
    if !User.where(user_id: params[:message][:from][:id], approved: true).none?
      edited_user = User.find_by(user_id: params[:message][:from][:id])
      old_name = edited_user.username
      edited_user.username = params[:message][:from][:first_name]
      if edited_user.save
        message = "Username updated from #{old_name} to #{params[:message][:from][:first_name]}"
      else
        message = "Unable to update name"
      end
    else
      message = "Sorry, only admins can use this command."
    end
    send_message(params[:message][:chat][:id], message)
  end

  def index
    if params[:message].present? && params[:message][:text] # Message received
      if params[:message][:from][:id] == params[:message][:chat][:id] # Ensure message came from private chat
        if params[:message][:entities].present? && params[:message][:entities][0][:type] == "bot_command"
          case params[:message][:text]
            when /^\/start/ # Initial start/welcome message
              start
            when /^\/approve/ # Approve admin request
              approve
            when /^\/revoke/ # Revoke admin access
              revoke
            when /^\/apply/ # Apply to gain admin access
              apply
            when /^\/help/ # List all commands
              help
            when /^\/list_admins/ # List all admins
              list_admins
            when /^\/list_blacklist/ # List all words on the blacklist
              list_blacklist
            when /^\/add_blacklist/ # Add word to blacklist
              add_blacklist
            when /^\/delete_blacklist/ # Remove word from blacklist
              delete_blacklist
            when /^\/list_messages/ # List all configurable messages
              list_messages
            when /^\/add_message/ # Add configurable message
              add_message
            when /^\/delete_message/ # Remove configurable message
              delete_message
            when /^\/edit_message/ # Edit configurable message
              edit_message
            when /^\/update_name/ # Update name in admin list
              update_name
            else
              send_message(params[:message][:chat][:id], "Sorry, command not found")
          end
        elsif params[:message][:reply_to_message].present? && params[:message][:reply_to_message][:from][:username] == Rails.application.credentials.bot_username! # Reply to bot
          case params[:message][:reply_to_message][:text]
            when /^Reply to this message with the new message in the format:/
              new_message
            when /^Reply to this message with the message_name you'd like to delete./
              destroy_message
            when /^Reply to this message with the edited message in the format:/
              save_message
            when /^Reply to this message with the words you would like to add to the blacklist/
              new_blacklist
            when /^Reply to this message with the words you would like to remove from the blacklist/
              destroy_blacklist
            else
              send_message(params[:message][:chat][:id], "I'm sorry, I don't quite understand")
          end
        end
      elsif params[:message][:chat][:id] == Rails.application.credentials.lobby_id! # Lobby chat
        if params[:message][:entities].present? && params[:message][:entities][0][:type] == "bot_command"
          case params[:message][:text]
            when /^\/link/ # Initial start/welcome message
              main_link
          end
        end
      elsif params[:message][:chat][:id] == Rails.application.credentials.main_id! # Main chat
        check_blacklist
      end
    elsif params[:chat_member].present? && params[:chat_member][:old_chat_member][:status] != "member" && params[:chat_member][:new_chat_member][:status] == "member" # Check for new chat member
      if params[:chat_member][:chat][:id] == Rails.application.credentials.lobby_id! # Lobby chat
        debug("New user entered the lobby")
        User.where(approved: true).each do |user|
          send_message(user.user_id, "New user in the CambFurs lobby:\n#{params[:chat_member][:new_chat_member][:user][:first_name]}")
        end
        send_message(params[:chat_member][:chat][:id], parse_details("lobby_welcome", params[:chat_member][:new_chat_member][:user][:first_name]))
      elsif params[:chat_member][:chat][:id] == Rails.application.credentials.main_id! # Main chat
        debug("New user entered the main chat")
        send_message(params[:chat_member][:chat][:id], parse_details("main_welcome", params[:chat_member][:new_chat_member][:user][:first_name]))
        remove_user(Rails.application.credentials.lobby_id!, params[:chat_member][:new_chat_member][:user][:id])
        request_link(Rails.application.credentials.main_id!)
      end
    end
  end

end
