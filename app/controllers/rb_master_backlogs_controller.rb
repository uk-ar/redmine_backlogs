include RbCommonHelper

class RbMasterBacklogsController < RbApplicationController
  unloadable

  def retrieve_selected_tracker_ids(selectable_trackers, default_trackers=nil)
    if ids = params[:tracker_ids]
      @selected_tracker_ids = (ids.is_a? Array) ? ids.collect { |id| id.to_i.to_s } : ids.split('/').collect { |id| id.to_i.to_s }
    else
      @selected_tracker_ids = (default_trackers || selectable_trackers).collect {|t| t.id.to_s }
    end
  end

  def get_versions
    @trackers = @project.trackers.find(:all, :order => 'position')
    retrieve_selected_tracker_ids(@trackers, @trackers.select {|t| t.is_in_roadmap?})
    @with_subprojects = params[:with_subprojects].nil? ? Setting.display_subprojects_issues? : (params[:with_subprojects] == '1')
    project_ids = @with_subprojects ? @project.self_and_descendants.collect(&:id) : [@project.id]
    
    @versions = @project.shared_versions || []
    @versions += @project.rolled_up_versions.visible if @with_subprojects
    @versions = @versions.uniq.sort
    @versions.reject! {|version| version.closed? || version.completed? } unless params[:completed]
    
    @issues_by_version = {}
    unless @selected_tracker_ids.empty?
      @versions.each do |version|
        issues = version.fixed_issues.visible.find(:all,
                                                   :include => [:project, :status, :tracker, :priority],
                                                   :conditions => {:tracker_id => @selected_tracker_ids, :project_id => project_ids},
                                                   :order => "#{Project.table_name}.lft, #{Tracker.table_name}.position, #{Issue.table_name}.id")
        @issues_by_version[version] = issues
      end
    end
    @versions.reject! {|version| !project_ids.include?(version.project_id) && @issues_by_version[version].blank?}
    @versions
  end

  def show
    product_backlog_stories = Story.product_backlog(@project)
    sprints = Sprint.find(:all,
                :order => 'sprint_start_date ASC, effective_date ASC',
                :conditions => [ "status = 'open' and id in (?) ", get_versions.collect{|p| p.id} ]
                )

    last_story = Story.find(
                          :first, 
                          :conditions => ["project_id=? AND tracker_id in (?)", @project, Story.trackers],
                          :order => "updated_on DESC"
                          )
    @last_update = (last_story ? last_story.updated_on : nil)
    @product_backlog = { :sprint => nil, :stories => product_backlog_stories }
    @sprint_backlogs = sprints.map{ |s| { :sprint => s, :stories => s.stories } }

    respond_to do |format|
      format.html { render :layout => "rb"}
    end
  end
  
end
