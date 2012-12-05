class ResponseController < ApplicationController
  helper :wiki
  helper :submitted_content
  helper :file
  
  def view
    @response = Response.find(params[:id])
    return if redirect_when_disallowed(@response)

    @map = @response.map
    get_content
  end
  
  def delete
    @response = Response.find(params[:id])
    return if redirect_when_disallowed(@response)

    map_id = @response.map.id
    @response.delete
    redirect_to :action => 'redirection', :id => map_id, :return => params[:return], :msg => "The response was deleted."
  end
  
  def edit
    @header = "Edit"
    @next_action = "update"
    @return = params[:return]
    @response = Response.find(params[:id]) 
    return if redirect_when_disallowed(@response)

    @modified_object = @response.id
    @map = @response.map           
    get_content    
    @review_scores = Array.new
    @questions.each{
      | question |
      @review_scores << Score.find_by_response_id_and_question_id(@response.id, question.id)
    }
    #**********************
    # Check whether this is Jen's assgt. & if so, use her rubric
    jkidd = User.find_by_name("jkidd")
    if jkidd && jkidd.id == @assignment.instructor_id && @title == "Review"
      if @assignment.id < 469
         @next_action = "custom_update"
         render :action => 'custom_response'
     else
         @next_action = "custom_update"
         render :action => 'custom_response_2011'
     end
    else
      # end of special code (except for the end below, to match the if above)
      #**********************
      render :action => 'response'
    end
  end  
  
  def update
    @response = Response.find(params[:id])
    return if redirect_when_disallowed(@response)
    @myid = @response.id
    msg = ""
    begin 
      @myid = @response.id
      @map = @response.map
      @response.update_attribute('additional_comment',params[:review][:comments])
      
      @questionnaire = @map.questionnaire
      questions = @questionnaire.questions
     
     
      params[:responses].each_pair do |k,v|
      
        score = Score.find_by_response_id_and_question_id(@response.id, questions[k.to_i].id)
          if(score == nil)
           score = Score.create(:response_id => @response.id, :question_id => questions[k.to_i].id, :score => v[:score], :comments => v[:comment])
          end
        score.update_attribute('score',v[:score])
        score.update_attribute('comments',v[:comment])
     end    
    rescue
      msg = "Your response was not saved. Cause: "+ $!
    end

    begin
       ResponseHelper.compare_scores(@response, @questionnaire)
       ScoreCache.update_cache(@response.id)
    
      msg = "Your response was successfully saved."
    rescue
      msg = "An error occurred while saving the response: "+$!
    end
    redirect_to :controller => 'response', :action => 'saving', :id => @map.id, :return => params[:return], :msg => msg
  end  
  
  def custom_update
    @response = Response.find(params[:id])
    @myid = @response.id
    msg = ""
    
    begin
      @myid = @response.id
      @map = @response.map
      @response.update_attribute('additional_comment',"")


      @questionnaire = @map.questionnaire
      questions = @questionnaire.questions

      for i in 0..questions.size-1
        score = Score.find_by_response_id_and_question_id(@response.id, questions[i.to_i].id)
        score.update_attribute('comments',params[:custom_response][i.to_s])
      end
    rescue
      msg = "#{@map.get_title} was not saved."
    end

    msg = "#{@map.get_title} was successfully saved."
    redirect_to :controller => 'response', :action => 'saving', :id => @map.id, :return => params[:return], :msg => msg
  end

  def new_feedback
    review = Response.find(params[:id])
    if review
      reviewer = AssignmentParticipant.find_by_user_id_and_parent_id(session[:user].id, review.map.assignment.id)
      map = FeedbackResponseMap.find_by_reviewed_object_id_and_reviewer_id(review.id, reviewer.id)
      if map.nil?
        map = FeedbackResponseMap.create(:reviewed_object_id => review.id, :reviewer_id => reviewer.id, :reviewee_id => review.map.reviewer.id)
      end
      redirect_to :action => 'new', :id => map.id, :return => "feedback"
    else
      redirect_to :back
    end
  end
  
  def new
    @header = "New"
    @next_action = "create"    
    @feedback = params[:feedback]
    @map = ResponseMap.find(params[:id])
    @return = params[:return]
    @modified_object = @map.id
    get_content  
    #**********************
    # Check whether this is Jen's assgt. & if so, use her rubric
    jkidd = User.find_by_name("jkidd")
    if jkidd && jkidd.id == @assignment.instructor_id && @title == "Review"
      if @assignment.id < 469
         @next_action = "custom_create"
         render :action => 'custom_response'
     else
         @next_action = "custom_create"
         render :action => 'custom_response_2011'
     end
    else
      # end of special code (except for the end below, to match the if above)
      #**********************
    render :action => 'response'
    end
  end
  
  def create
    @map = ResponseMap.find(params[:id])
    @res = 0
    msg = ""
    error_msg = ""
    begin
      @response = Response.create(:map_id => @map.id, :additional_comment => params[:review][:comments])
      @res = @response.id
      @questionnaire = @map.questionnaire
      questions = @questionnaire.questions
      if (@map.type.to_s == 'QuizResponseMap')
        questions.each_with_index do |question, k|
           if @questionnaire.quiz_question_type == "Multiple Choice - checked"
             for selected_item in params[('checked_items_'+question.id.to_s).to_sym]
               print "Selected Item: " + selected_item
               selected_option = QuestionAdvice.find(selected_item)
               score = Score.create(:response_id => @response.id, :question_id => questions[k.to_i].id, :score => selected_option.score, :comments => selected_option.advice)
               #if selected_option.score == 0.to_s
               #  break
               #end
             end
           elsif @questionnaire.quiz_question_type == "Multiple Choice - radio"
             selected_option_id =  params[('option_'+k.to_s).to_sym]
             selected_option = QuestionAdvice.find(selected_option_id)
           elsif @questionnaire.quiz_question_type == "Essay"
             selected_option = QuestionAdvice.new
             selected_option.score = 1
             selected_option.advice = params[('question_'+ question.id.to_s).to_sym]
           elsif @questionnaire.quiz_question_type == "True False"
             selected_option_id =  params[('option_'+k.to_s).to_sym]
             if selected_option_id == 1.to_s
               question.question_advices.each { |question_advice|
                  if question_advice.advice == "TRUE"
                    selected_option = question_advice
                    break
                  end
               }
             else
               question.question_advices.each { |question_advice|
                 if question_advice.advice == "FALSE"
                   selected_option = question_advice
                   break
                 end
               }
             end
           end
           if @questionnaire.quiz_question_type != "Multiple Choice - checked"
              score = Score.create(:response_id => @response.id, :question_id => questions[k.to_i].id, :score => selected_option.score, :comments => selected_option.advice)
           end
        end
      else
        params[:responses].each_pair do |k,v|
          score = Score.create(:response_id => @response.id, :question_id => questions[k.to_i].id, :score => v[:score], :comments => v[:comment])
        end
      end
    rescue
      @response.delete
      error_msg = "Your response was not saved. Cause: " + $!
    end

    begin
      if (@map.type.to_s != 'QuizResponseMap')
        ResponseHelper.compare_scores(@response, @questionnaire)
      end
      ScoreCache.update_cache(@res)
      #add new rating and store the new average rating for quiz questions
      i=0
      @map.questionnaire.questions.each{
          | question |
        selected_difficulty_rating_first = params[:difficulty_rating][i.to_s]
        total_number_of_ratings = question.number_of_ratings
        total_value_of_rating = question.average_difficulty_rating.to_f * total_number_of_ratings.to_f
        new_total_value_of_rating = total_value_of_rating.to_f + (selected_difficulty_rating_first.to_s).to_f
        total_number_of_ratings +=1
        question.number_of_ratings = total_number_of_ratings
        question.average_difficulty_rating = new_total_value_of_rating.to_f / total_number_of_ratings.to_f
        question.save
        i+=1
      }

      @map.save
      msg = "Your response was successfully saved."
    rescue
      @response.delete
      error_msg = "Your response was not saved. Cause: " + $!
    end
    redirect_to :controller => 'response', :action => 'saving', :id => @map.id, :return => params[:return], :msg => msg, :error_msg => error_msg
  end      
  
  def custom_create
    @map = ResponseMap.find(params[:id])
    @response = Response.create(:map_id => @map.id, :additional_comment => "")
    @res = @response.id
    @questionnaire = @map.questionnaire
    questions = @questionnaire.questions
    
    for i in 0..questions.size-1
        # Local variable score is unused; can it be removed?
        score = Score.create(:response_id => @response.id, :question_id => questions[i].id, :score => @questionnaire.max_question_score, :comments => params[:custom_response][i.to_s])
          

    end
    msg = "#{@map.get_title} was successfully saved."
    
    redirect_to :controller => 'response', :action => 'saving', :id => @map.id, :return => params[:return], :msg => msg
  end

  def saving   
    @map = ResponseMap.find(params[:id])
    @return = params[:return]
    @map.notification_accepted = false;
    @map.save
    
    redirect_to :action => 'redirection', :id => @map.id, :return => params[:return], :msg => params[:msg], :error_msg => params[:error_msg]
  end
  
  def redirection
    flash[:error] = params[:error_msg] unless params[:error_msg] and params[:error_msg].empty?
    flash[:note]  = params[:msg] unless params[:msg] and params[:msg].empty?
    
    @map = ResponseMap.find(params[:id])
    if params[:return] == "feedback"
      redirect_to :controller => 'grades', :action => 'view_my_scores', :id => @map.reviewer.id
    elsif params[:return] == "teammate"
      redirect_to :controller => 'student_team', :action => 'view', :id => @map.reviewer.id
    elsif params[:return] == "instructor"
      redirect_to :controller => 'grades', :action => 'view', :id => @map.assignment.id
    else
      if(@map.type.to_s == 'QuizResponseMap')
        redirect_to :controller => 'student_quiz', :action => 'list', :id => @map.reviewer.id
      else
        redirect_to :controller => 'student_review', :action => 'list', :id => @map.reviewer.id
      end
    end
  end
  
  private
    
  def get_content    
    @title = @map.get_title
    if (@map.type.to_s=="QuizResponseMap")
      quiz_id = @map.reviewed_object_id
      participant_id = QuizQuestionnaire.find(quiz_id).instructor_id
      assignment_id = Participant.find(participant_id).parent_id
      assignment =  Assignment.find(assignment_id)
      @map.assignment = Assignment.find(assignment_id)
    end
    @assignment = @map.assignment
    @participant = @map.reviewer
    @contributor = @map.contributor
    @questionnaire = @map.questionnaire
    @questions = @questionnaire.questions
    @min = @questionnaire.min_question_score
    @max = @questionnaire.max_question_score

  end
  
  def redirect_when_disallowed(response)
    # For author feedback, participants need to be able to read feedback submitted by other teammates.
    # If response is anything but author feedback, only the person who wrote feedback should be able to see it.
    if response.map.read_attribute(:type) == 'FeedbackResponseMap' && response.map.assignment.team_assignment
      team = response.map.reviewer.team
      unless team.has_user session[:user]
        redirect_to '/denied?reason=You are not on the team that wrote this feedback'
        return true
      end
    else
      return true unless current_user_id?(response.map.reviewer.user_id)
    end
    
    return false
  end
end
