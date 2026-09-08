import { Controller } from "@hotwired/stimulus";

// Connects to data-controller="capas--questionnaire-generation"
export default class extends Controller {
  static targets = ["retryButton", 
    "messagesContainer",
    "actionButtons",
    "loadingState",
    "completionState",
    "progressText",
    "progressBar",
    "progressPercent",
    "regenerateButton",
    "acceptButton"
  ];

  static values = { capaId: String };

  connect() {
    this.translations = {
      questionLabel: this.element.dataset.questionLabel || 'Question %{number}',
      answerLabel: this.element.dataset.answerLabel || 'Answer',
      draftNotice: this.element.dataset.draftNotice || '',
      acceptedLabel: this.element.dataset.acceptedLabel || 'Accepted',
      acceptedHeading: this.element.dataset.acceptedHeading || 'Question %{number} - Accepted',
      regenerateLabel: this.element.dataset.regenerateLabel || 'Regenerate',
      completeLabel: this.element.dataset.completeLabel || 'Complete'
    };

    this.currentQuestion = 1;
    this.currentPair = null;
    this.existingQuestions = {};
    this.isGenerating = false;
    this.isComplete = false;
    this.regeneratingQuestionNumber = null;
    this.isCascadeRegenerating = false;
    
    // Ensure modal is closed and hidden when controller connects
    const modal = this.element;
    if (modal && modal.tagName === 'DIALOG') {
      // Hide the modal
      modal.style.display = 'none';
      
      // Remove open attribute if present
      if (modal.hasAttribute('open')) {
        modal.removeAttribute('open');
      }
      
      // Close the dialog if it's open
      if (typeof modal.close === 'function') {
        try {
          modal.close();
        } catch (e) {
          // Dialog might not be open, ignore error
        }
      }
    }
    
    // Listen for custom open event (fallback if controller not found when button clicked)
    this.element.addEventListener('questionnaire:open', this.handleOpenEvent.bind(this));
  }

  disconnect() {
    this.element.removeEventListener('questionnaire:open', this.handleOpenEvent.bind(this));
  }

  handleOpenEvent(event) {
    const { capaId } = event.detail || {};
    if (capaId) {
      this.capaIdValue = capaId;
    }
    this.initializeAndStart().catch(error => {
      console.error('Error initializing questionnaire generation:', error);
    });
  }

  async openModal(event) {
    // This method is called from the modal's controller instance
    const modal = this.element;
    if (!modal || modal.tagName !== 'DIALOG') {
      // If called from outside, find the modal
      const modalElement = document.getElementById('questionnaireGenerationModal');
      if (!modalElement) return;
      
      // Get the controller instance from the modal
      let controller = null;
      if (window.Stimulus) {
        controller = window.Stimulus.getControllerForElementAndIdentifier(modalElement, 'capas--questionnaire-generation');
      } else if (window.application) {
        controller = window.application.getControllerForElementAndIdentifier(modalElement, 'capas--questionnaire-generation');
      }
      
      if (!controller) {
        console.error('Questionnaire generation controller not found on modal');
        return;
      }
      
      // Get capaId from button if provided
      if (event && event.currentTarget) {
        const capaId = event.currentTarget.dataset.capaId;
        if (capaId) {
          controller.capaIdValue = capaId;
        }
      }
      
      await controller.initializeAndStart();
      return;
    }

    // Get capaId from button if provided
    if (event && event.currentTarget) {
      const capaId = event.currentTarget.dataset.capaId;
      if (capaId) {
        this.capaIdValue = capaId;
      }
    }

    await this.initializeAndStart();
  }

  async initializeAndStart() {
    // Get the modal element - use this.element if it's the dialog, otherwise find it
    let modal = this.element;
    if (!modal || modal.tagName !== 'DIALOG') {
      modal = document.getElementById('questionnaireGenerationModal');
    }
    
    if (!modal) {
      console.error('Modal element not found!');
      alert('Modal not found. Please refresh the page.');
      return;
    }
    
    // Show the modal - only if explicitly called (not on page load)
    try {
      if (modal.tagName === 'DIALOG' && typeof modal.showModal === 'function') {
        modal.style.display = '';
        modal.showModal();
      } else {
        modal.style.display = 'block';
        modal.setAttribute('open', '');
      }
    } catch (error) {
      console.error('Error showing modal:', error);
      // Fallback
      modal.style.display = 'block';
      modal.setAttribute('open', '');
    }
    
    // Initialize state
    this.currentQuestion = 1;
    this.currentPair = null;
    this.existingQuestions = {};
    this.isGenerating = false;
    this.isComplete = false;
    this.regeneratingQuestionNumber = null;
    
    // Clear messages - check if targets exist
    try {
      if (this.hasMessagesContainerTarget) {
        this.messagesContainerTarget.innerHTML = '';
      }
      if (this.hasActionButtonsTarget) {
        this.actionButtonsTarget.style.display = 'none';
      }
      if (this.hasLoadingStateTarget) {
        this.loadingStateTarget.style.display = 'none';
      }
      if (this.hasCompletionStateTarget) {
        this.completionStateTarget.style.display = 'none';
      }
    } catch (error) {
      console.error('Error clearing targets:', error);
    }
    
    // Load existing state
    try {
      await this.loadState();
    } catch (error) {
      console.error('Error loading state:', error);
    }
    
    // Check if questionnaire is complete
    if (this.isComplete) {
      // Display all questions with regenerate buttons
      this.displayAllQuestionsForRegeneration();
    } else if (this.currentQuestion <= 5) {
      // If not complete, generate first question
      try {
        await this.generatePair();
      } catch (error) {
        console.error('Error generating pair:', error);
      }
    } else {
      this.showCompletion();
    }
  }

  closeModal() {
    const modal = document.getElementById('questionnaireGenerationModal') || this.element;
    if (modal) {
      // Close the dialog
      if (typeof modal.close === 'function') {
        modal.close();
      }
      // Hide the modal
      modal.style.display = 'none';
      // Remove open attribute
      if (modal.hasAttribute('open')) {
        modal.removeAttribute('open');
      }
      // Reload page to show updated questionnaire
      window.location.reload();
    }
  }

  async loadState() {
    try {
      const response = await fetch(`/dashboard/capa_management/${this.capaIdValue}/questionnaire/start`, {
        method: 'POST',
        headers: {
          'X-CSRF-Token': document.querySelector('meta[name="csrf-token"]').content,
          'Accept': 'application/json',
          'Content-Type': 'application/json'
        }
      });

      if (response.ok) {
        const result = await response.json();
        this.currentQuestion = result.current_question || 1;
        this.existingQuestions = result.existing_questions || {};
        this.isComplete = result.is_complete || false;
        
        // Display existing questions (only if not in regeneration mode)
        if (!this.isComplete) {
          Object.keys(this.existingQuestions).forEach(num => {
            const qa = this.existingQuestions[num];
            this.addAcceptedMessage(parseInt(num), qa.question, qa.answer);
          });
        }
        
        this.updateProgress();
      }
    } catch (error) {
      console.error('Error loading state:', error);
    }
  }

  async generatePair() {
    if (this.isGenerating) {
      return;
    }
    
    if (this.currentQuestion > 5) {
      this.showCompletion();
      return;
    }
    
    this.isGenerating = true;
    this.showLoading();
    this.hideActionButtons();

    try {
      const response = await fetch(`/dashboard/capa_management/${this.capaIdValue}/questionnaire/generate_pair`, {
        method: 'POST',
        headers: {
          'X-CSRF-Token': document.querySelector('meta[name="csrf-token"]').content,
          'Accept': 'application/json',
          'Content-Type': 'application/json'
        },
        body: JSON.stringify({
          question_number: this.currentQuestion
        })
      });

      if (response.ok) {
        const result = await response.json();
        this.currentPair = {
          question: result.question,
          answer: result.answer,
          question_number: result.question_number
        };
        
        // If regenerating a specific question, remove the old accepted message first
        if (this.regeneratingQuestionNumber) {
          const oldMessage = this.messagesContainerTarget.querySelector(`[data-question-number="${this.regeneratingQuestionNumber}"][data-message-type="accepted"]`);
          if (oldMessage) {
            oldMessage.remove();
          }
        }
        
        this.addGeneratedMessage(result.question_number, result.question, result.answer);
        this.hideLoading();
        this.showActionButtons();
      } else {
        const error = await response.json().catch(() => ({}));
        this.offerRetry(error.error || 'Failed to generate question pair');
      }
    } catch (error) {
      console.error('Error generating pair:', error);
      this.offerRetry('Network error. Please try again.');
    } finally {
      this.isGenerating = false;
    }
  }

  // A failed question is not a dead end. What was accepted is already saved
  // server-side, so the only thing to do is try this question again.
  offerRetry(message) {
    this.hideLoading();
    this.showError(`${message} ${this.element.dataset.failedLabel || ''}`.trim());
    if (this.hasActionButtonsTarget) this.actionButtonsTarget.style.display = 'block';
    if (this.hasRegenerateButtonTarget) this.regenerateButtonTarget.style.display = 'none';
    if (this.hasAcceptButtonTarget) this.acceptButtonTarget.style.display = 'none';
    if (this.hasRetryButtonTarget) this.retryButtonTarget.style.display = 'flex';
  }

  async retryPair() {
    if (this.isGenerating) return;
    if (this.hasRetryButtonTarget) this.retryButtonTarget.style.display = 'none';
    if (this.hasRegenerateButtonTarget) this.regenerateButtonTarget.style.display = '';
    if (this.hasAcceptButtonTarget) this.acceptButtonTarget.style.display = '';
    await this.generatePair();
  }

  async regeneratePair() {
    if (this.isGenerating || !this.currentPair) return;
    
    this.isGenerating = true;
    this.showLoading();
    this.hideActionButtons();

    // Remove the last generated message
    const lastMessage = this.messagesContainerTarget.lastElementChild;
    if (lastMessage && lastMessage.dataset.messageType === 'generated') {
      lastMessage.remove();
    }

    try {
      const response = await fetch(`/dashboard/capa_management/${this.capaIdValue}/questionnaire/regenerate_pair`, {
        method: 'POST',
        headers: {
          'X-CSRF-Token': document.querySelector('meta[name="csrf-token"]').content,
          'Accept': 'application/json',
          'Content-Type': 'application/json'
        },
        body: JSON.stringify({
          question_number: this.currentQuestion
        })
      });

      if (response.ok) {
        const result = await response.json();
        this.currentPair = {
          question: result.question,
          answer: result.answer,
          question_number: result.question_number
        };
        
        this.addGeneratedMessage(result.question_number, result.question, result.answer);
        this.hideLoading();
        this.showActionButtons();
      } else {
        const error = await response.json();
        this.showError(error.error || 'Failed to regenerate question pair');
        this.hideLoading();
      }
    } catch (error) {
      console.error('Error regenerating pair:', error);
      this.showError('Network error. Please try again.');
      this.hideLoading();
    } finally {
      this.isGenerating = false;
    }
  }

  // The reviewer's edits, if any, are what gets accepted.
  //
  // Only the field belonging to the pair currently under review counts. An
  // accepted message stays on the page, and reading the first editable field
  // on the page returned question one's answer for every later question.
  editedAnswer() {
    const current = this.messagesContainerTarget.querySelector('[data-message-type="generated"]');
    const field = current ? current.querySelector('[data-generated-answer]') : null;
    const edited = field ? field.value.trim() : '';
    return edited || this.currentPair.answer;
  }

  // Once accepted, the answer is a fact of record rather than a draft: the
  // editable field becomes plain text so it can neither be edited nor mistaken
  // for the next question's field.
  freezeAcceptedAnswer(message) {
    const field = message.querySelector('[data-generated-answer]');
    if (!field) return;

    const text = document.createElement('div');
    text.className = 'text-sm text-[#0D1120] message-content whitespace-pre-line';
    text.textContent = field.value;
    field.replaceWith(text);

    const notice = message.querySelector('p');
    if (notice) notice.remove();
  }

  async acceptPair() {
    if (!this.currentPair || this.isGenerating) return;

    this.currentPair.answer = this.editedAnswer();
    
    this.isGenerating = true;
    this.regenerateButtonTarget.disabled = true;
    this.acceptButtonTarget.disabled = true;

    try {
      const response = await fetch(`/dashboard/capa_management/${this.capaIdValue}/questionnaire/accept_pair`, {
        method: 'POST',
        headers: {
          'X-CSRF-Token': document.querySelector('meta[name="csrf-token"]').content,
          'Accept': 'application/json',
          'Content-Type': 'application/json'
        },
        body: JSON.stringify({
          question_number: this.currentPair.question_number,
          question: this.currentPair.question,
          answer: this.currentPair.answer
        })
      });

      if (response.ok) {
        const result = await response.json();
        
        // Store accepted data for later updates
        const acceptedQuestionNumber = this.currentPair.question_number;
        const acceptedQuestion = this.currentPair.question;
        const acceptedAnswer = this.currentPair.answer;
        
        // Mark current pair as accepted
        this.existingQuestions[acceptedQuestionNumber] = {
          question: acceptedQuestion,
          answer: acceptedAnswer
        };
        
        // Check if we're in regeneration mode (cascade)
        if (this.isCascadeRegenerating) {
          // Remove the generated message
          const generatedMessage = this.messagesContainerTarget.querySelector(`[data-message-type="generated"]`);
          if (generatedMessage) {
            generatedMessage.remove();
          }
          
          // Add the new accepted message with regenerate button
          this.addAcceptedMessage(
            acceptedQuestionNumber,
            this.currentPair.question,
            this.currentPair.answer,
            true // show regenerate button
          );
          
          this.updateQuestionnaireSection(acceptedQuestionNumber, acceptedQuestion, acceptedAnswer, result.root_cause);
          
          this.currentPair = null;
          
          // Continue cascading through remaining questions
          if (acceptedQuestionNumber < 5) {
            this.isGenerating = false;
            this.regenerateButtonTarget.disabled = false;
            this.acceptButtonTarget.disabled = false;
            
            this.currentQuestion = acceptedQuestionNumber + 1;
            this.updateProgress();
            await this.generatePair();
          } else {
            // Final question accepted – finish cascade and redisplay regeneration view
            this.isComplete = true;
            this.isCascadeRegenerating = false;
            this.regeneratingQuestionNumber = null;
            this.isGenerating = false;
            this.regenerateButtonTarget.disabled = false;
            this.acceptButtonTarget.disabled = false;
            this.displayAllQuestionsForRegeneration();
          }
        } else {
          // Normal flow - update the message to show it's accepted
          const lastMessage = this.messagesContainerTarget.lastElementChild;
          if (lastMessage && lastMessage.dataset.messageType === 'generated') {
            this.freezeAcceptedAnswer(lastMessage);
            lastMessage.dataset.messageType = 'accepted';
            const acceptIndicator = document.createElement('div');
            acceptIndicator.className = 'text-xs text-[#3F9011] font-medium mt-2 flex items-center space-x-1';
            acceptIndicator.innerHTML = '<svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M5 13l4 4L19 7"></path></svg><span>' + this.translations.acceptedLabel + '</span>';
            const messageContent = lastMessage.querySelector('.message-content');
            if (messageContent) {
              messageContent.appendChild(acceptIndicator);
            }
          }
          
          this.currentPair = null;
          
          this.updateQuestionnaireSection(acceptedQuestionNumber, acceptedQuestion, acceptedAnswer, result.root_cause);
          
          if (result.is_complete) {
            this.isGenerating = false;
            this.regenerateButtonTarget.disabled = false;
            this.acceptButtonTarget.disabled = false;
            this.showCompletion();
          } else {
            const nextQuestion = result.next_question;
            if (nextQuestion && nextQuestion <= 5) {
              this.isGenerating = false;
              this.regenerateButtonTarget.disabled = false;
              this.acceptButtonTarget.disabled = false;
              this.currentQuestion = nextQuestion;
              this.updateProgress();
              await this.generatePair();
            } else {
              console.error('Invalid next_question received:', nextQuestion);
              this.isGenerating = false;
              this.regenerateButtonTarget.disabled = false;
              this.acceptButtonTarget.disabled = false;
              this.showError('Invalid question number received. Please refresh the page.');
            }
          }
        }
      } else {
        const error = await response.json();
        this.isGenerating = false;
        this.regenerateButtonTarget.disabled = false;
        this.acceptButtonTarget.disabled = false;
        this.showError(error.error || 'Failed to accept question pair');
      }
    } catch (error) {
      console.error('Error accepting pair:', error);
      this.isGenerating = false;
      this.regenerateButtonTarget.disabled = false;
      this.acceptButtonTarget.disabled = false;
      this.showError('Network error. Please try again.');
    }
  }

  updateQuestionnaireSection(questionNumber, question, answer, rootCause) {
    const questionRow = document.querySelector(`[data-question-index="${questionNumber}"]`);
    if (questionRow) {
      const questionView = questionRow.querySelector('[data-capas--questionnaire-target="questionView"]');
      if (questionView) {
        questionView.textContent = question;
      }
      const answerView = questionRow.querySelector('[data-capas--questionnaire-target="answerView"] p');
      if (answerView) {
        answerView.textContent = answer;
      }
    }
    
    if (rootCause) {
      const rootCauseView = document.querySelector('[data-capas--questionnaire-target="rootCauseView"]');
      if (rootCauseView) {
        rootCauseView.textContent = rootCause;
      }
      const rootCauseEdit = document.querySelector('[data-capas--questionnaire-target="rootCauseEdit"]');
      if (rootCauseEdit) {
        rootCauseEdit.value = rootCause;
      }
    }
  }
  
  clearQuestionnaireSectionFrom(startNumber) {
    for (let i = startNumber; i <= 5; i++) {
      const questionRow = document.querySelector(`[data-question-index="${i}"]`);
      if (questionRow) {
        const questionView = questionRow.querySelector('[data-capas--questionnaire-target="questionView"]');
        const answerView = questionRow.querySelector('[data-capas--questionnaire-target="answerView"] p');
        if (questionView) questionView.textContent = '';
        if (answerView) answerView.textContent = '';
      }
    }
    
    const rootCauseView = document.querySelector('[data-capas--questionnaire-target="rootCauseView"]');
    if (rootCauseView) rootCauseView.textContent = '';
    const rootCauseEdit = document.querySelector('[data-capas--questionnaire-target="rootCauseEdit"]');
    if (rootCauseEdit) rootCauseEdit.value = '';
  }

  addGeneratedMessage(questionNumber, question, answer) {
    const messageDiv = document.createElement('div');
    messageDiv.className = 'flex flex-col space-y-2';
    messageDiv.dataset.messageType = 'generated';
    
    // The answer is a draft, not a finding: it is labelled as such and stays
    // editable so a reviewer can correct an unsupported claim before accepting
    // it, rather than choosing only between Regenerate and Accept.
    messageDiv.innerHTML = `
      <div class="bg-[#F7F7FD] border border-[#E3E3E3] rounded-lg p-4">
        <div class="text-xs font-semibold text-[#797C81] mb-2">${this.translations.questionLabel.replace('%{number}', questionNumber)}</div>
        <div class="text-sm font-medium text-[#0D1120] mb-3">${this.escapeHtml(question)}</div>
        <div class="text-xs font-semibold text-[#797C81] mb-2">${this.translations.answerLabel}</div>
        <textarea class="w-full text-sm text-[#0D1120] bg-white border border-[#E3E3E3] rounded-md p-3 resize-y focus:outline-none focus:ring-2 focus:ring-[#5C3984] focus:border-[#5C3984]"
                  rows="4" data-generated-answer>${this.escapeHtml(answer)}</textarea>
        <p class="mt-2 text-xs text-[#797C81]">${this.escapeHtml(this.translations.draftNotice)}</p>
      </div>
    `;
    
    this.messagesContainerTarget.appendChild(messageDiv);
    this.scrollToBottom();
  }

  addAcceptedMessage(questionNumber, question, answer, showRegenerateButton = false) {
    const messageDiv = document.createElement('div');
    messageDiv.className = 'flex flex-col space-y-2';
    messageDiv.dataset.messageType = 'accepted';
    messageDiv.dataset.questionNumber = questionNumber;
    
    let regenerateButtonHtml = '';
    if (showRegenerateButton) {
      regenerateButtonHtml = `
        <div class="mt-3 flex justify-end">
          <button type="button" 
                  class="px-3 py-1.5 bg-[#5C3984] rounded-lg text-xs font-medium text-white hover:opacity-80 disabled:opacity-50 disabled:cursor-not-allowed flex items-center space-x-1"
                  data-action="click->capas--questionnaire-generation#regenerateSpecificQuestion"
                  data-question-number="${questionNumber}">
            <svg class="w-3 h-3" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M4 4v5h.582m15.356 2A8.001 8.001 0 004.582 9m0 0H9m11 11v-5h-.581m0 0a8.003 8.003 0 01-15.357-2m15.357 2H15" />
            </svg>
            <span>${this.translations.regenerateLabel}</span>
          </button>
        </div>
      `;
    }
    
    messageDiv.innerHTML = `
      <div class="bg-[#E0F9DE] border border-[#3F9011] rounded-lg p-4">
        <div class="text-xs font-semibold text-[#3F9011] mb-2 flex items-center space-x-1">
          <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M5 13l4 4L19 7"></path>
          </svg>
          <span>${this.translations.acceptedHeading.replace('%{number}', questionNumber)}</span>
        </div>
        <div class="text-sm font-medium text-[#0D1120] mb-3">${this.escapeHtml(question)}</div>
        <div class="text-xs font-semibold text-[#797C81] mb-2">${this.translations.answerLabel}</div>
        <div class="text-sm text-[#0D1120]">${this.escapeHtml(answer)}</div>
        ${regenerateButtonHtml}
      </div>
    `;
    
    this.messagesContainerTarget.appendChild(messageDiv);
    this.scrollToBottom();
  }

  showLoading() {
    this.loadingStateTarget.style.display = 'block';
    this.actionButtonsTarget.style.display = 'none';
  }

  hideLoading() {
    this.loadingStateTarget.style.display = 'none';
  }

  showActionButtons() {
    this.actionButtonsTarget.style.display = 'block';
    this.loadingStateTarget.style.display = 'none';
  }

  hideActionButtons() {
    this.actionButtonsTarget.style.display = 'none';
  }

  showCompletion() {
    this.actionButtonsTarget.style.display = 'none';
    this.loadingStateTarget.style.display = 'none';
    this.completionStateTarget.style.display = 'block';
    this.updateProgress();
    this.progressBarTarget.style.width = '100%';
    this.progressPercentTarget.textContent = '100%';
    this.progressTextTarget.textContent = this.translations.completeLabel;
  }

  updateProgress() {
    let progress;
    if (this.isComplete) {
      progress = 100;
    } else {
      progress = ((this.currentQuestion - 1) / 5) * 100;
    }
    
    this.progressBarTarget.style.width = `${progress}%`;
    this.progressPercentTarget.textContent = `${Math.round(progress)}%`;
    
    if (this.isComplete) {
      this.progressTextTarget.textContent = 'Complete';
    } else if (this.currentQuestion <= 5) {
      this.progressTextTarget.textContent = `Question ${this.currentQuestion} of 5`;
    } else {
      this.progressTextTarget.textContent = 'Complete';
    }
  }

  displayAllQuestionsForRegeneration() {
    // Clear any existing messages
    this.messagesContainerTarget.innerHTML = '';
    
    // Hide action buttons and completion state
    this.hideActionButtons();
    this.completionStateTarget.style.display = 'none';
    
    // Display all 5 questions with regenerate buttons
    Object.keys(this.existingQuestions).sort((a, b) => parseInt(a) - parseInt(b)).forEach(num => {
      const qa = this.existingQuestions[num];
      this.addAcceptedMessage(parseInt(num), qa.question, qa.answer, true); // true = show regenerate button
    });
    
    // Update progress to show complete
    this.updateProgress();
  }

  regenerateSpecificQuestion(event) {
    const questionNumber = parseInt(event.currentTarget.dataset.questionNumber);
    if (this.isGenerating) {
      return;
    }
    
    // Set regeneration mode and clear downstream state so later questions will be regenerated
    this.isCascadeRegenerating = true;
    this.regeneratingQuestionNumber = questionNumber;
    this.currentQuestion = questionNumber;
    this.isComplete = false;
    
    // Drop previously accepted downstream questions locally
    Object.keys(this.existingQuestions).forEach(num => {
      if (parseInt(num) >= questionNumber) {
        delete this.existingQuestions[num];
      }
    });
    
    // Remove downstream messages from the UI
    this.messagesContainerTarget.querySelectorAll('[data-question-number]').forEach(el => {
      const num = parseInt(el.dataset.questionNumber);
      if (!Number.isNaN(num) && num >= questionNumber) {
        el.remove();
      }
    });
    // Remove any generated (non-accepted) messages
    this.messagesContainerTarget.querySelectorAll('[data-message-type="generated"]').forEach(el => el.remove());
    
    // Clear questionnaire section display for target and downstream questions/root cause
    this.clearQuestionnaireSectionFrom(questionNumber);
    
    this.updateProgress();
    
    // Generate the pair
    this.generatePair();
  }

  showError(message) {
    const errorDiv = document.createElement('div');
    errorDiv.className = 'bg-[#FFF1F0] border border-[#EA4034] rounded-lg p-4 text-sm text-[#EA4034]';
    errorDiv.textContent = message;
    this.messagesContainerTarget.appendChild(errorDiv);
    this.scrollToBottom();
    
    // Remove error after 5 seconds
    setTimeout(() => {
      if (errorDiv.parentNode) {
        errorDiv.remove();
      }
    }, 5000);
  }

  scrollToBottom() {
    this.messagesContainerTarget.scrollTop = this.messagesContainerTarget.scrollHeight;
  }

  escapeHtml(text) {
    const div = document.createElement('div');
    div.textContent = text;
    return div.innerHTML;
  }
}

