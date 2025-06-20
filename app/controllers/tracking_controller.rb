class TrackingController < ApplicationController
  skip_before_action :verify_authenticity_token

  def identify
    identify_params = process_identify_params
    person = Person.find_or_initialize_by(uuid: identify_params[:uuid])

    identify_params[:properties]&.each do |key, value|
      if person.properties[key] != value
        person.properties["old_#{key}"] = person.properties[key]
      end
      person.properties[key] = value
    end

    if person.save
      render json: { status: "success" }, status: :created
    else
      render json: { status: "error", errors: person.errors.full_messages }, status: :unprocessable_entity
    end
  end

  def event
    event_params = process_event_params
    event_params[:event_data][:browser_full_version] = browser.full_version
    event_params[:event_data][:browser_name] = browser.name
    event_params[:event_data][:browser_meta] = browser.meta
    event_params[:event_data][:browser_version] = browser.version
    if browser.bot?
      event_params[:event_data][:browser_bot] = true
      event_params[:event_data][:browser_bot_name] = browser.bot.name
    else
      event_params[:event_data][:browser_bot] = false
    end
    event_params[:event_data][:browser_mobile] = browser.device.mobile?
    event_params[:event_data][:browser_console] = browser.device.console?

    event_params[:event_data][:browser_device_name] = browser.device.name
    event_params[:event_data][:browser_device_id] = browser.device.id

    event_params[:event_data][:browser_platform_id] = browser.platform.id
    event_params[:event_data][:browser_platform_version] = browser.platform.version
    event_params[:event_data][:browser_platform_name] = browser.platform.name

    captured_headers = [
      "cf-ipcity", "cf-ipcountry", "cf-ipcontinent", "cf-iplongitude", "cf-iplatitude",
      "cf-region", "cf-region-code", "cf-metro-code", "cf-postal-code", "cf-timezone", "cf-connecting-ip"
    ]
    additional_headers = [ :formatted_fbclid, :user_agent, :browser_platform_name, :browser_mobile, :browser_name, :js_user_agent, :referrer, :fbp ]

    captured_headers.each do |header|
      if request.headers[header]
        event_params[:event_data][header.gsub("-", "_")] = request.headers[header]
      end
    end
    event_params[:event_data][:user_agent] = request.user_agent
    if event_params[:event_data][:selected_params] && event_params[:event_data][:selected_params][:fbclid].present?
      event_params[:event_data][:formatted_fbclid] = "fb.1.#{Time.now.utc.to_i * 1000}.#{event_params[:event_data][:selected_params][:fbclid]}"
    end
    # Remove keys longer than 15 characters from all_params
    if event_params[:event_data][:all_params].is_a?(Hash)
      event_params[:event_data][:all_params].delete_if { |key, _| key.to_s.length > 15 }
    end

    event = Event.new(event_params)
    event.timestamp ||= Time.current # Ensure timestamp is set if not provided
    person = Person.find_or_create_by(uuid: event_params[:uuid])
    if event.event_type == "visit"
      # Update browser info and secondary_id

      # Update initial and latest URL parameters
      person.initial_params ||= {}
      person.latest_params ||= {}

      event_params[:event_data][:selected_params]&.each do |key, value|
        person.initial_params[key] ||= value
      end

      event_params[:event_data][:selected_params]&.each do |key, value|
        person.latest_params[key] = value
        person.latest_params[key.to_s + "_ts"] = event.timestamp
      end

      captured_headers.each do |header|
        if request.headers[header]
          person.latest_params[header.to_s.gsub("-", "_")] = request.headers[header]
          person.latest_params[header.to_s.gsub("-", "_") + "_ts"] = event.timestamp
          person.initial_params[header.to_s.gsub("-", "_")] ||= request.headers[header]
        end
      end

      additional_headers.each do |header|
        if event_params[:event_data][header]
          person.latest_params[header.to_s.gsub("-", "_")] = event_params[:event_data][header]
          person.latest_params[header.to_s.gsub("-", "_") + "_ts"] = event.timestamp
          person.initial_params[header.to_s.gsub("-", "_")] ||= event_params[:event_data][header]
        end
      end

      if !person.save
        render json: { status: "error", errors: person.errors.full_messages }, status: :unprocessable_entity
        return
      end
    end
    if event.save
        render json: { status: "success" }, status: :created
    else
        render json: { status: "error", errors: event.errors.full_messages }, status: :unprocessable_entity
    end
  end

  def update_email
    email_params = process_update_email_params

    # Find or create person by SA_UUID (Person UUID)
    person = Person.find_or_initialize_by(uuid: email_params[:SA_UUID])

    # Initialize properties if not present
    person.properties ||= {}

    # Only update email if it doesn't already exist
    if person.properties["email"].blank?
      person.properties["email"] = email_params[:email]
      person.properties["oir_source"] = email_params[:oir_source]

      if person.save
        render json: { status: "success", message: "Email added successfully" }, status: :ok
      else
        render json: { status: "error", errors: person.errors.full_messages }, status: :unprocessable_entity
      end
    else
      render json: { status: "success", message: "Email already exists, not overwritten" }, status: :ok
    end
  end

  private
  def process_identify_params
    params[:tracking].permit(
      :uuid,
      properties: {}
    )
  end

  def process_event_params
    params[:tracking].permit(
      :uuid,
      :event_type,
      :timestamp,
      event_data: {}
    )
  end

  def process_update_email_params
    params.permit(:email, :SA_UUID, :oir_source)
  end
end
