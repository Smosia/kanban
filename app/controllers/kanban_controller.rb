class KanbanController < ApplicationController
  unloadable
  before_action :global_authorize
  #
  # Display kanban board
  #
  def index 
    # Do not cache on browser back
    response.headers['Cache-Control'] = 'no-store, no-cache, must-revalidate, max-age=0, post-check=0, pre-check=0'
    response.headers['Pragma'] = 'no-cache'
    
    # Discard session
    if params[:clear].to_i == 1 then
      discard_session
    end

    # Restore session
    restore_params_from_session

    # Initialize params
    initialize_params

    # Store session
    store_params_to_session

    # Get user to display avator
    @user = User.find(@user_id.to_i)

    # Get current project
    if @project_id.blank? then
      @project = nil
    else
      @project = Project.find(@project_id)
    end
    
    # Get users for assignee filetr
    if @project_all == "1" then
      @selectable_users = User.where(type: "User").where(status: 1)
    else
      @selectable_users = @project.users
    end

    # Get groups for group filetr
    if @project_all == "1" then
      @selectable_groups = Group.where(type: "Group")
    else
      members = Member.where(project_id: @project.id)
      member_user_ids = []
      members.each {|member|
        member_user_ids << member.user_id
      }
      @selectable_groups = Group.where(type: "Group").where(id: member_user_ids)
    end

    # Create array of user IDs belongs to the group
    @user_id_array = []
    if @group_id == "unspecified" then
      # Case no group selected
      @user_id_array << @user_id.to_i
    else
      # Case group selected
      @selectable_groups.each {|group|
        if group.id == @group_id.to_i
          @user_id_array = group.user_ids
        end
      }
    end

    # Remove inactive users from array of display users
    copied_user_id_array = @user_id_array.dup
    copied_user_id_array.each {|id|
      if !@selectable_users.ids.include?(id) then
        @user_id_array.delete(id)
      end
    }

    # Move current user to head
    selected_user_index = @user_id_array.index(@user_id.to_i)
    if @user_id_array.length > 1 && selected_user_index != nil then
      swap_id = @user_id_array[0]
      @user_id_array[selected_user_index] = swap_id
      @user_id_array[0] = @user_id.to_i
    end

    # When system settings of issue_group_assignment is true,
    # add group ID to array of display users
    @group_id_array = []
    if Setting.issue_group_assignment? then
      if @group_id == "unspecified" then
        @selectable_groups.each {|group|
            @user_id_array << group.id
            @group_id_array << group.id
        }
      else
        @user_id_array << @group_id.to_i
        @group_id_array << @group_id.to_i
      end
    end

    # Create hash of users/groups name
    @user_and_group_names_hash = {}
    @selectable_users.each {|user|
      @user_and_group_names_hash[user.id] = user.name
    }
    @selectable_groups.each {|group|
      @user_and_group_names_hash[group.id] = group.name
    }

    # Get all status orderby position
    @issue_statuses = IssueStatus.all.order("position ASC")
    @issue_statuses_hash = {}
    @issue_statuses.each {|issue_status|
      @issue_statuses_hash[issue_status.id.to_i] = issue_status.name
    }

    # Get statuses for issue closed
    @done_issue_statuses = IssueStatus.where(is_closed: 1)
    @done_issue_statuses_array = []
    @done_issue_statuses.each {|issue_status|
      @done_issue_statuses_array << issue_status.id
    }

    # Updated datetime for filter
    if @updated_within == "0" then
      time_from = Time.at(0)
    else
      time_from = Time.now - 3600 * 24 * @updated_within.to_i
    end
    updated_from = time_from.strftime("%Y-%m-%d 00:00:00")

    # Closed datetime for filter
    time_from = Time.now - 3600 * 24 * @done_within.to_i
    closed_from = time_from.strftime("%Y-%m-%d 00:00:00")

    # Get issues related to display users
    issues_for_projects = Issue.where(assigned_to_id: @user_id_array)
      .where("updated_on >= '" + updated_from + "'")
      .where(is_private: 0)
      .limit(Constants::SELECT_LIMIT)

    # Unique project IDs
    unique_project_id_array = []
    if @project_all == "1" then
      issues_for_projects.each {|issue|
        if unique_project_id_array.include?(issue.project.id.to_i) == false then
          unique_project_id_array << issue.project.id.to_i
        end
      }
    else
      # When select one project, add subproject IDs
      unique_project_id_array << @project.id.to_i
      subprojects = Project.where(parent_id: @project.id.to_i)
      subprojects.each {|subproject|
        unique_project_id_array << subproject.id.to_i
      }
    end

    # Display no assignee issue
    @user_id_array << nil;

    # Declaring variables
    @issues_hash = {}
    @wip_hash = {}
    @over_wip = 0

    # Get issues using status loop
    @status_fields_array.each {|status_id|
      if @done_issue_statuses_array.include?(status_id) == false then
        # Case not closed status
        @issues_hash[status_id] = Issue.where(assigned_to_id: @user_id_array)
          .where(project_id: unique_project_id_array)
          .where(status: status_id)
          .where("updated_on >= '" + updated_from + "'")
          .where(is_private: 0)
          .limit(Constants::SELECT_LIMIT)
          .order("CASE assigned_to_id WHEN '" + @user_id.to_s + "' THEN 1 ELSE 2 END, assigned_to_id DESC")  # Sort @user_id first
        # Count WIP issues
        if status_id == Constants::WIP_COUNT_STATUS_FIELD then
          @user_id_array.each {|uid|
            wip_counter = 0
            @issues_hash[status_id].each {|issue|
              if issue.assigned_to_id == uid then
                if @version_id == "unspecified" then
                  wip_counter += 1
                else
                  if issue.fixed_version_id == @version_id.to_i then
                    wip_counter += 1
                  end
                end
              end
            }
            # Save count value
            if uid != nil then
              @wip_hash[uid] = wip_counter
            end
          }
        end
      else
        # Case closed status
        @issues_hash[status_id] = Issue.where(assigned_to_id: @user_id_array)
          .where(project_id: unique_project_id_array)
          .where(status: status_id)
          .where("updated_on >= '" + closed_from + "'")
          .where(is_private: 0)
          .limit(Constants::SELECT_LIMIT)
          .order("CASE assigned_to_id WHEN '" + @user_id.to_s + "' THEN 1 ELSE 2 END, assigned_to_id DESC")  # Sort @user_id first
      end
    }

    # Hide user without issues
    if Constants::DISPLAY_USER_WITHOUT_ISSUES != 1 then
      remove_user_without_issues
    end
    
    if @project == nil && Constants::DISPLAY_ISSUES_WITHOUT_PROJECT == "0" then
      @user_id_array.clear
    end

  end
  
  private

  #
  # Discard session
  #
  def discard_session
    session[:kanban] = nil
  end

  #
  # Store session
  #
  def store_params_to_session
    session_hash = {}
    session_hash["updated_within"] = @updated_within
    session_hash["done_within"] = @done_within
    session_hash["user_id"] = @user_id
    session_hash["group_id"] = @group_id
    session_hash["project_all"] = @project_all
    session_hash["version_id"] = @version_id
    session_hash["status_fields"] = @status_fields
    session_hash["wip_max"] = @wip_max
    session[:kanban] = session_hash
  end

  #
  # Restore session
  #
  def restore_params_from_session
    session_hash = session[:kanban]
    
    # Days since upadated date
    if !session_hash.blank? && params[:updated_within].blank?
      @updated_within = session_hash["updated_within"]
    else
      @updated_within = params[:updated_within]
    end

    # Days since closed date
    if !session_hash.blank? && params[:done_within].blank?
      @done_within = session_hash["done_within"]
    else
      @done_within = params[:done_within]
    end

    # Display user ID
    if !session_hash.blank? && params[:user_id].blank?
      @user_id = session_hash["user_id"]
    else
      @user_id = params[:user_id]
    end

    # Display group ID
    if !session_hash.blank? && params[:group_id].blank?
      @group_id = session_hash["group_id"]
    else
      @group_id = params[:group_id]
    end

    # Project display flag
    if !session_hash.blank? && params[:project_all].blank?
      @project_all = session_hash["project_all"]
    else
      @project_all = params[:project_all]
    end

    # Display version ID
    if !session_hash.blank? && params[:version_id].blank?
      @version_id = session_hash["version_id"]
    else
      @version_id = params[:version_id]
    end

    # Selected statuses
    if !session_hash.blank? && params[:status_fields].blank?
      @status_fields = session_hash["status_fields"]
    else
      @status_fields = params[:status_fields]
    end

    # Max number of WIP issue
    if !session_hash.blank? && params[:wip_max].blank?
      @wip_max = session_hash["wip_max"]
    else
      @wip_max = params[:wip_max]
    end
  end

  #
  # Initialize params
  # When value is invalid, set it to default. 
  #
  def initialize_params
    # Days since upadated date
    if @updated_within.nil? || @updated_within.to_i == 0 then
      @updated_within = Constants::DEFAULT_VALUE_UPDATED_WITHIN
    end
    
    # Days since closed date
    if @done_within.nil? || @done_within.to_i == 0 then
      @done_within = Constants::DEFAULT_VALUE_DONE_WITHIN
    end

    # User ID
    if @user_id.nil? || @user_id.to_i == 0 then
      @user_id = @current_user.id
    end
    
    # Group ID
    if @group_id.nil? || @group_id.to_i == 0 then
      @group_id = "unspecified"
    end

    # Project display flag
    @project_id = params[:project_id]
    if @project_id.blank? then
      # Case move from application menu
      @project_all = "1"
    else
      # Case move from project menu
      if @project_all.blank? then
        @project_all = "0"
      end
    end

    # Version ID
    if @version_id.nil? || @version_id.to_i == 0 || @project_all == "1" then
      @version_id = "unspecified"
    end

    # Array of status ID for display
    @status_fields_array = []
    if !@status_fields.blank? then
      @status_fields.each {|id,chk|
        if chk == "1"
          @status_fields_array << id.to_i
        end
      }
    else
      # Default
      @status_fields_array = Constants::DEFAULT_STATUS_FIELD_VALUE_ARRAY
    end

    # Max number of WIP issue (default)
    if @wip_max.nil? || @wip_max.to_i == 0 then
      @wip_max = Constants::DEFAULT_VALUE_WIP_MAX
    end
  end

  #
  # Remove user without issues from @user_id_array
  #
  def remove_user_without_issues
    copied_user_id_array = @user_id_array.dup
    copied_user_id_array.each {|uid|
      number_of_issues = 0
      @status_fields_array.each {|status_id|
        @issues_hash[status_id].each {|issue|
          if issue.assigned_to_id == uid then
            number_of_issues += 1
          end
        }
      }
      if !uid.nil? && number_of_issues == 0 then
        @user_id_array.delete(uid)
      end
    }
  end

  #
  # User logged in
  #
  def set_user
    @current_user ||= User.current
  end

  #
  # Need Login
  #
  def global_authorize
    set_user
    render_403 unless @current_user.type == 'User'
  end

end
