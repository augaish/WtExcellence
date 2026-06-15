import { Controller } from "@hotwired/stimulus";

// Connects to data-controller="capas--questionnaire"
export default class extends Controller {
  static targets = [
    "regenerateButton", 
    "regenerateButtonText", 
    "loadingSpinner", 
    "questionnaireContainer", 
    "questionnaireContent", 
    "rootCauseContainer",
    "editButton",
    "editModeButtons",
    "viewModeButtons",
    "saveButton",
    "questionRow",
    "questionView",
    "questionEdit",
    "answerView",
    "answerEdit",
    "deleteButton",
    "addQuestionContainer",
    "rootCauseView",
    "rootCauseEdit",
    "writeButton",
    "writeButtonText",
    "writeLoadingSpinner",
    "rootCauseRegenerateButton",
    "rootCauseRegenerateSpinner",
    "rootCauseRegenerateText",
    "rootCauseViewButtons",
    "rootCauseEditButtons",
    "rootCauseSaveButton"
  ];

  connect() {
    this.isEditMode = false;
    this.originalData = null;
    this.rootCauseIsEditMode = false;
    this.originalRootCauseValue = null;
  }

  async writeQuestionnaire(event) {
    event.preventDefault();
    
    const button = event.currentTarget;
    const capaId = button.dataset.capaId;
    
    if (!this.hasWriteButtonTarget || !this.hasWriteButtonTextTarget || !this.hasWriteLoadingSpinnerTarget) {
      this.showError("Unable to create questionnaire. Please refresh the page.");
      return;
    }

    const buttonText = this.writeButtonTextTarget;
    const spinner = this.writeLoadingSpinnerTarget;
    const writeBtn = this.writeButtonTarget;

    try {
      // Show loading state
      writeBtn.disabled = true;
      buttonText.textContent = "Creating...";
      spinner.classList.remove("hidden");

      // Make API call
      const response = await fetch(`/dashboard/capa_management/${capaId}/questionnaire`, {
        method: "POST",
        headers: {
          "X-CSRF-Token": document.querySelector('meta[name="csrf-token"]').content,
          "Content-Type": "application/json",
        },
      });

      if (response.ok) {
        const result = await response.json();
        
        // Show toast notification
        if (result.notification_html) {
          this.dispatchToast(result.notification_html);
        }
        
        // Reload page after successful creation
        setTimeout(() => {
          window.location.reload();
        }, 500);
      } else {
        const error = await response.json();
        if (error.notification_html) {
          this.dispatchToast(error.notification_html);
        } else {
          this.showError(error.error || "Failed to create questionnaire. Please try again.");
        }
      }
    } catch (error) {
      console.error("Questionnaire creation error:", error);
      this.showError("An error occurred. Please try again.");
    } finally {
      // Reset button state (though page will reload on success)
      writeBtn.disabled = false;
      buttonText.textContent = "Write Questionnaire";
      spinner.classList.add("hidden");
    }
  }

  async regenerate(event) {
    event.preventDefault();
    
    const button = event.currentTarget;
    const capaId = button.dataset.capaId;
    const buttonText = this.regenerateButtonTextTarget;
    const spinner = this.loadingSpinnerTarget;
    const regenerateBtn = this.regenerateButtonTarget;

    try {
      // Show loading state
      regenerateBtn.disabled = true;
      buttonText.textContent = "Generating...";
      spinner.classList.remove("hidden");

      // Make API call
      const response = await fetch(`/dashboard/capa_management/${capaId}/regenerate_questionnaire`, {
        method: "POST",
        headers: {
          "X-CSRF-Token": document.querySelector('meta[name="csrf-token"]').content,
          "Content-Type": "application/json",
        },
      });

      if (response.ok) {
        const result = await response.json();
        
        // Update the questionnaire content
        this.updateQuestionnaireUI(result.questionnaire);
        
        // Show success message if provided
        if (result.notification_html) {
          this.dispatchToast(result.notification_html);
        } else {
          this.showSuccess("Questionnaire regenerated successfully!");
        }
      } else {
        const error = await response.json();
        if (error.notification_html) {
          this.dispatchToast(error.notification_html);
        } else {
          this.showError(error.error || "Failed to regenerate questionnaire. Please try again.");
        }
      }
    } catch (error) {
      console.error("Questionnaire regeneration error:", error);
      this.showError("An error occurred. Please try again.");
    } finally {
      // Reset button state
      regenerateBtn.disabled = false;
      buttonText.textContent = "Re-generate";
      spinner.classList.add("hidden");
    }
  }

  async regenerateRootCause(event) {
    event.preventDefault();
    
    const button = event.currentTarget;
    const capaId = button.dataset.capaId;
    
    if (!capaId) {
      this.showError("Unable to determine CAPA. Please refresh the page.");
      return;
    }
    
    const spinner = this.hasRootCauseRegenerateSpinnerTarget ? this.rootCauseRegenerateSpinnerTarget : null;
    const buttonText = this.hasRootCauseRegenerateTextTarget ? this.rootCauseRegenerateTextTarget : null;
    
    try {
      button.disabled = true;
      if (buttonText) buttonText.textContent = "Generating...";
      if (spinner) spinner.classList.remove("hidden");
      
      const response = await fetch(`/dashboard/capa_management/${capaId}/questionnaire/regenerate_root_cause`, {
        method: "POST",
        headers: {
          "X-CSRF-Token": document.querySelector('meta[name="csrf-token"]').content,
          "Content-Type": "application/json",
        },
      });
      
      if (response.ok) {
        const result = await response.json();
        
        if (this.hasRootCauseViewTarget) {
          this.rootCauseViewTarget.textContent = result.root_cause || "";
        }
        if (this.hasRootCauseEditTarget) {
          this.rootCauseEditTarget.value = result.root_cause || "";
        }
        
        if (result.notification_html) {
          this.dispatchToast(result.notification_html);
        } else {
          this.showSuccess("Root cause regenerated successfully!");
        }
      } else {
        const error = await response.json();
        if (error.notification_html) {
          this.dispatchToast(error.notification_html);
        } else {
          this.showError(error.error || "Failed to regenerate root cause. Please try again.");
        }
      }
    } catch (error) {
      console.error("Root cause regeneration error:", error);
      this.showError("An error occurred. Please try again.");
    } finally {
      button.disabled = false;
      if (buttonText) buttonText.textContent = "Re-generate";
      if (spinner) spinner.classList.add("hidden");
    }
  }

  toggleRootCauseEdit(event) {
    event.preventDefault();
    
    if (this.rootCauseIsEditMode) {
      this.cancelRootCauseEdit();
    } else {
      this.enterRootCauseEditMode();
    }
  }
  
  enterRootCauseEditMode() {
    if (!this.hasRootCauseEditTarget || !this.hasRootCauseViewTarget) return;
    
    this.rootCauseIsEditMode = true;
    this.originalRootCauseValue = this.rootCauseViewTarget.textContent || "";
    
    if (this.hasRootCauseViewButtonsTarget) {
      this.rootCauseViewButtonsTarget.classList.add("hidden");
    }
    if (this.hasRootCauseEditButtonsTarget) {
      this.rootCauseEditButtonsTarget.classList.remove("hidden");
    }
    
    this.rootCauseEditTarget.value = this.originalRootCauseValue;
    this.rootCauseViewTarget.classList.add("hidden");
    this.rootCauseEditTarget.classList.remove("hidden");
    this.rootCauseEditTarget.focus();
  }
  
  exitRootCauseEditMode() {
    this.rootCauseIsEditMode = false;
    
    if (this.hasRootCauseViewButtonsTarget) {
      this.rootCauseViewButtonsTarget.classList.remove("hidden");
    }
    if (this.hasRootCauseEditButtonsTarget) {
      this.rootCauseEditButtonsTarget.classList.add("hidden");
    }
    
    this.rootCauseViewTarget.classList.remove("hidden");
    this.rootCauseEditTarget.classList.add("hidden");
  }
  
  async saveRootCause(event) {
    event.preventDefault();
    
    if (!this.hasRootCauseEditTarget) return;
    
    const button = event.currentTarget;
    const capaId = button.dataset.capaId;
    if (!capaId) {
      this.showError("Unable to determine CAPA. Please refresh the page.");
      return;
    }
    
    const buttonText = button.querySelector("span");
    const originalText = buttonText ? buttonText.textContent : null;
    
    try {
      button.disabled = true;
      if (buttonText) buttonText.textContent = "Saving...";
      
      const response = await fetch(`/dashboard/capa_management/${capaId}/questionnaire`, {
        method: "PATCH",
        headers: {
          "X-CSRF-Token": document.querySelector('meta[name="csrf-token"]').content,
          "Content-Type": "application/json",
        },
        body: JSON.stringify({
          questionnaire: {
            root_cause: this.rootCauseEditTarget.value
          }
        }),
      });
      
      if (response.ok) {
        const result = await response.json();
        
        if (result.questionnaire && result.questionnaire.root_cause) {
          this.rootCauseViewTarget.textContent = result.questionnaire.root_cause;
          this.rootCauseEditTarget.value = result.questionnaire.root_cause;
        } else {
          const value = this.rootCauseEditTarget.value || "";
          this.rootCauseViewTarget.textContent = value;
        }
        
        this.exitRootCauseEditMode();
        
        if (result.notification_html) {
          this.dispatchToast(result.notification_html);
        } else {
          this.showSuccess("Root cause updated successfully!");
        }
      } else {
        const error = await response.json();
        if (error.notification_html) {
          this.dispatchToast(error.notification_html);
        } else {
          this.showError(error.error || "Failed to update root cause. Please try again.");
        }
      }
    } catch (err) {
      console.error("Root cause save error:", err);
      this.showError("An error occurred. Please try again.");
    } finally {
      button.disabled = false;
      if (buttonText) buttonText.textContent = originalText || "Save";
    }
  }
  
  cancelRootCauseEdit(event) {
    event.preventDefault();
    
    if (this.originalRootCauseValue !== null) {
      this.rootCauseEditTarget.value = this.originalRootCauseValue;
      this.rootCauseViewTarget.textContent = this.originalRootCauseValue;
    }
    
    this.exitRootCauseEditMode();
  }

  toggleRootCauseEdit(event) {
    event?.preventDefault();
    
    if (this.rootCauseIsEditMode) {
      this.cancelRootCauseEdit();
    } else {
      this.enterRootCauseEditMode();
    }
  }
  
  enterRootCauseEditMode() {
    if (!this.hasRootCauseEditTarget || !this.hasRootCauseViewTarget) return;
    
    this.rootCauseIsEditMode = true;
    this.originalRootCauseValue = this.rootCauseEditTarget.value;
    
    if (this.hasRootCauseViewButtonsTarget) {
      this.rootCauseViewButtonsTarget.classList.add("hidden");
    }
    if (this.hasRootCauseEditButtonsTarget) {
      this.rootCauseEditButtonsTarget.classList.remove("hidden");
    }
    
    this.rootCauseViewTarget.classList.add("hidden");
    this.rootCauseEditTarget.classList.remove("hidden");
    this.rootCauseEditTarget.focus();
  }
  
  exitRootCauseEditMode() {
    this.rootCauseIsEditMode = false;
    
    if (this.hasRootCauseViewButtonsTarget) {
      this.rootCauseViewButtonsTarget.classList.remove("hidden");
    }
    if (this.hasRootCauseEditButtonsTarget) {
      this.rootCauseEditButtonsTarget.classList.add("hidden");
    }
    
    if (this.hasRootCauseViewTarget) {
      this.rootCauseViewTarget.classList.remove("hidden");
      this.rootCauseViewTarget.textContent = this.rootCauseEditTarget.value || "";
    }
    this.rootCauseEditTarget.classList.add("hidden");
  }
  
  async saveRootCause(event) {
    event.preventDefault();
    
    if (!this.hasRootCauseEditTarget) return;
    
    const button = this.hasRootCauseSaveButtonTarget ? this.rootCauseSaveButtonTarget : event.currentTarget;
    const capaId = button?.dataset.capaId;
    
    if (!capaId) {
      this.showError("Unable to determine CAPA. Please refresh the page.");
      return;
    }
    
    const buttonText = button.querySelector("span");
    const originalText = buttonText ? buttonText.textContent : null;
    
    try {
      button.disabled = true;
      if (buttonText) buttonText.textContent = "Saving...";
      
      const response = await fetch(`/dashboard/capa_management/${capaId}/questionnaire`, {
        method: "PATCH",
        headers: {
          "X-CSRF-Token": document.querySelector('meta[name="csrf-token"]').content,
          "Content-Type": "application/json",
        },
        body: JSON.stringify({
          questionnaire: {
            root_cause: this.rootCauseEditTarget.value
          }
        }),
      });
      
      if (response.ok) {
        const result = await response.json();
        
        if (this.hasRootCauseViewTarget) {
          this.rootCauseViewTarget.textContent = this.rootCauseEditTarget.value || "";
        }
        this.exitRootCauseEditMode();
        
        if (result.notification_html) {
          this.dispatchToast(result.notification_html);
        } else {
          this.showSuccess("Root cause updated successfully!");
        }
      } else {
        const error = await response.json();
        if (error.notification_html) {
          this.dispatchToast(error.notification_html);
        } else {
          this.showError(error.error || "Failed to update root cause. Please try again.");
        }
      }
    } catch (error) {
      console.error("Root cause save error:", error);
      this.showError("An error occurred. Please try again.");
    } finally {
      button.disabled = false;
      if (buttonText) buttonText.textContent = originalText || "Save";
    }
  }
  
  cancelRootCauseEdit(event) {
    event?.preventDefault();
    
    if (this.hasRootCauseEditTarget && this.originalRootCauseValue !== null) {
      this.rootCauseEditTarget.value = this.originalRootCauseValue;
      if (this.hasRootCauseViewTarget) {
        this.rootCauseViewTarget.textContent = this.originalRootCauseValue || "";
      }
    }
    
    this.exitRootCauseEditMode();
  }

  toggleEditMode() {
    if (this.isEditMode) {
      this.exitEditMode();
    } else {
      this.enterEditMode();
    }
  }

  enterEditMode() {
    this.isEditMode = true;
    
    // Store original data for cancel (read from view fields first)
    this.originalData = this.getQuestionnaireDataFromViews();
    
    // Show edit mode buttons, hide view mode buttons
    this.editModeButtonsTarget.classList.remove("hidden");
    this.viewModeButtonsTarget.classList.add("hidden");
    
    // Show edit fields, hide view fields
    this.questionViewTargets.forEach((view, index) => {
      const edit = this.questionEditTargets[index];
      if (edit) {
        edit.value = view.textContent || "";
        view.classList.add("hidden");
        edit.classList.remove("hidden");
      }
    });
    
    this.answerViewTargets.forEach((view, index) => {
      const edit = this.answerEditTargets[index];
      if (edit) {
        const answerText = view.querySelector("p");
        edit.value = answerText ? answerText.textContent || "" : "";
        view.classList.add("hidden");
        edit.classList.remove("hidden");
      }
    });
    
    this.deleteButtonTargets.forEach(btn => btn.classList.remove("hidden"));
    
    // Show add question button if less than 5 questions (check after copying values)
    // Count non-empty questions
    let visibleQuestions = 0;
    this.questionEditTargets.forEach(edit => {
      if (edit.value.trim() !== "") {
        visibleQuestions++;
      }
    });
    
    if (visibleQuestions < 5 && this.hasAddQuestionContainerTarget) {
      this.addQuestionContainerTarget.classList.remove("hidden");
    }
  }

  getQuestionnaireDataFromViews() {
    const data = {
      question_1: "",
      question_2: "",
      question_3: "",
      question_4: "",
      question_5: "",
      answer_1: "",
      answer_2: "",
      answer_3: "",
      answer_4: "",
      answer_5: ""
    };

    // Collect question data from views
    this.questionViewTargets.forEach((view, index) => {
      const edit = this.questionEditTargets[index];
      if (edit) {
        const field = edit.dataset.questionField;
        if (field && data.hasOwnProperty(field)) {
          data[field] = view.textContent || "";
        }
      }
    });

    // Collect answer data from views
    this.answerViewTargets.forEach((view, index) => {
      const edit = this.answerEditTargets[index];
      if (edit) {
        const field = edit.dataset.answerField;
        if (field && data.hasOwnProperty(field)) {
          const answerText = view.querySelector("p");
          data[field] = answerText ? answerText.textContent || "" : "";
        }
      }
    });

    // Collect root cause
    if (this.hasRootCauseViewTarget) {
      data.root_cause = this.rootCauseViewTarget.textContent || "";
    }

    return data;
  }

  exitEditMode() {
    this.isEditMode = false;
    
    // Show view mode buttons, hide edit mode buttons
    this.editModeButtonsTarget.classList.add("hidden");
    this.viewModeButtonsTarget.classList.remove("hidden");
    
    // Show view fields, hide edit fields
    this.questionViewTargets.forEach(view => view.classList.remove("hidden"));
    this.questionEditTargets.forEach(edit => edit.classList.add("hidden"));
    this.answerViewTargets.forEach(view => view.classList.remove("hidden"));
    this.answerEditTargets.forEach(edit => edit.classList.add("hidden"));
    this.deleteButtonTargets.forEach(btn => btn.classList.add("hidden"));
    
    // Hide add question button
    if (this.hasAddQuestionContainerTarget) {
      this.addQuestionContainerTarget.classList.add("hidden");
    }
  }

  async saveQuestionnaire(event) {
    event.preventDefault();
    
    const button = event.currentTarget;
    const capaId = button.dataset.capaId;
    const saveBtn = this.saveButtonTarget;

    try {
      // Disable save button
      saveBtn.disabled = true;
      saveBtn.querySelector("span").textContent = "Saving...";

      // Collect questionnaire data
      const questionnaireData = this.getQuestionnaireData();

      // Make API call
      const response = await fetch(`/dashboard/capa_management/${capaId}/questionnaire`, {
        method: "PATCH",
        headers: {
          "X-CSRF-Token": document.querySelector('meta[name="csrf-token"]').content,
          "Content-Type": "application/json",
        },
        body: JSON.stringify({ questionnaire: questionnaireData }),
      });

      if (response.ok) {
        const result = await response.json();
        
        // Update view fields with saved data from backend response
        if (result.questionnaire) {
          this.updateViewFields(result.questionnaire);
        } else {
          this.updateViewFields(questionnaireData);
        }
        
        // Exit edit mode
        this.exitEditMode();
        
        // Show success message if provided
        if (result.notification_html) {
          this.dispatchToast(result.notification_html);
        } else {
          this.showSuccess("Questionnaire saved successfully!");
        }
      } else {
        const error = await response.json();
        if (error.notification_html) {
          this.dispatchToast(error.notification_html);
        } else {
          this.showError(error.error || "Failed to save questionnaire. Please try again.");
        }
      }
    } catch (error) {
      console.error("Questionnaire save error:", error);
      this.showError("An error occurred. Please try again.");
    } finally {
      // Reset button state
      saveBtn.disabled = false;
      saveBtn.querySelector("span").textContent = "Save";
    }
  }

  cancelEdit() {
    // Restore original data
    if (this.originalData) {
      this.restoreOriginalData();
    }
    
    // Exit edit mode
    this.exitEditMode();
  }

  addQuestion() {
    const visibleQuestions = this.getVisibleQuestionCount();
    
    if (visibleQuestions >= 5) {
      this.showError("Maximum of 5 questions allowed.");
      return;
    }

    // Find first empty question slot
    const questionFields = ["question_1", "question_2", "question_3", "question_4", "question_5"];
    const answerFields = ["answer_1", "answer_2", "answer_3", "answer_4", "answer_5"];
    
    for (let i = 0; i < 5; i++) {
      const questionEdit = this.questionEditTargets.find(
        edit => edit.dataset.questionField === questionFields[i]
      );
      
      if (questionEdit && questionEdit.value.trim() === "") {
        // Focus on the empty question field
        questionEdit.focus();
        return;
      }
    }
    
    // If all questions have content, show error
    this.showError("All question slots are filled. Please delete a question first or edit existing ones.");
  }

  removeQuestion(event) {
    const button = event.currentTarget;
    const questionRow = button.closest('[data-capas--questionnaire-target="questionRow"]');
    
    if (!questionRow) return;
    
    const visibleQuestions = this.getVisibleQuestionCount();
    
    if (visibleQuestions <= 1) {
      this.showError("At least one question is required.");
      return;
    }
    
    // Clear the question and answer fields
    const questionEdit = questionRow.querySelector('[data-capas--questionnaire-target="questionEdit"]');
    const answerEdit = questionRow.querySelector('[data-capas--questionnaire-target="answerEdit"]');
    
    if (questionEdit) questionEdit.value = "";
    if (answerEdit) answerEdit.value = "";
    
    // Update add question button visibility
    const currentVisible = this.getVisibleQuestionCount();
    if (currentVisible < 5 && this.hasAddQuestionContainerTarget) {
      this.addQuestionContainerTarget.classList.remove("hidden");
    }
  }

  getQuestionnaireData() {
    const data = {
      question_1: "",
      question_2: "",
      question_3: "",
      question_4: "",
      question_5: "",
      answer_1: "",
      answer_2: "",
      answer_3: "",
      answer_4: "",
      answer_5: "",
      root_cause: ""
    };

    // Collect question data
    this.questionEditTargets.forEach(edit => {
      const field = edit.dataset.questionField;
      if (field && data.hasOwnProperty(field)) {
        data[field] = edit.value || "";
      }
    });

    // Collect answer data
    this.answerEditTargets.forEach(edit => {
      const field = edit.dataset.answerField;
      if (field && data.hasOwnProperty(field)) {
        data[field] = edit.value || "";
      }
    });

    return data;
  }

  getVisibleQuestionCount() {
    let count = 0;
    this.questionEditTargets.forEach(edit => {
      if (edit.value.trim() !== "") {
        count++;
      }
    });
    return count;
  }

  restoreOriginalData() {
    if (!this.originalData) return;

    // Restore questions
    this.questionEditTargets.forEach(edit => {
      const field = edit.dataset.questionField;
      if (field && this.originalData.hasOwnProperty(field)) {
        edit.value = this.originalData[field] || "";
      }
    });

    // Restore answers
    this.answerEditTargets.forEach(edit => {
      const field = edit.dataset.answerField;
      if (field && this.originalData.hasOwnProperty(field)) {
        edit.value = this.originalData[field] || "";
      }
    });

    // Restore root cause
    if (this.hasRootCauseEditTarget) {
      this.rootCauseEditTarget.value = this.originalData.root_cause || "";
    }
  }

  updateViewFields(data) {
    // Update question views
    this.questionViewTargets.forEach((view, index) => {
      const questionEdit = this.questionEditTargets[index];
      if (questionEdit) {
        const field = questionEdit.dataset.questionField;
        if (field && data.hasOwnProperty(field)) {
          view.textContent = data[field] || "";
        }
      }
    });

    // Update answer views
    this.answerViewTargets.forEach((view, index) => {
      const answerEdit = this.answerEditTargets[index];
      if (answerEdit) {
        const field = answerEdit.dataset.answerField;
        if (field && data.hasOwnProperty(field)) {
          const answerText = view.querySelector("p");
          if (answerText) {
            answerText.textContent = data[field] || "";
          }
        }
      }
    });

    // Update root cause view
    if (this.hasRootCauseViewTarget && Object.prototype.hasOwnProperty.call(data, "root_cause")) {
      this.rootCauseViewTarget.textContent = data.root_cause || "";
    }
  }

  updateQuestionnaireUI(questionnaireData) {
    // If we have a questionnaire container, update it
    if (this.hasQuestionnaireContainerTarget && this.hasQuestionnaireContentTarget) {
      const content = this.questionnaireContentTarget;
      const rootCause = this.hasRootCauseContainerTarget ? this.rootCauseContainerTarget : null;

      // Update questions and answers
      const questions = [
        questionnaireData.question_1,
        questionnaireData.question_2,
        questionnaireData.question_3,
        questionnaireData.question_4,
        questionnaireData.question_5,
      ];
      
      const answers = [
        questionnaireData.answer_1,
        questionnaireData.answer_2,
        questionnaireData.answer_3,
        questionnaireData.answer_4,
        questionnaireData.answer_5,
      ];

      // Update each question-answer pair
      const questionRows = content.querySelectorAll(".px-6.py-4");
      questionRows.forEach((row, index) => {
        const questionDiv = row.querySelector('[data-capas--questionnaire-target="questionView"]');
        const answerDiv = row.querySelector('[data-capas--questionnaire-target="answerView"] p');
        
        if (questionDiv && questions[index]) {
          questionDiv.textContent = questions[index];
        }
        if (answerDiv && answers[index]) {
          answerDiv.textContent = answers[index];
        }
      });

      // Update root cause
      if (rootCause && questionnaireData.root_cause) {
        const rootCauseText = rootCause.querySelector('[data-capas--questionnaire-target="rootCauseView"]');
        if (rootCauseText) {
          rootCauseText.textContent = questionnaireData.root_cause;
        }
      }
    } else {
      // If no questionnaire exists yet, reload the page to show the new questionnaire
      // Delay slightly to ensure any toast notifications are visible
      setTimeout(() => {
        window.location.reload();
      }, 500);
    }
  }

  updateQuestionnaireValues(questionnaire) {
    // Update question and answer values
    for (let i = 1; i <= 5; i++) {
      const questionView = this.element.querySelector(`[data-question-field="question_${i}"]`)?.closest('[data-capas--questionnaire-target="questionRow"]')?.querySelector('[data-capas--questionnaire-target="questionView"]');
      const questionEdit = this.element.querySelector(`[data-question-field="question_${i}"]`);
      const answerView = this.element.querySelector(`[data-answer-field="answer_${i}"]`)?.closest('[data-capas--questionnaire-target="questionRow"]')?.querySelector('[data-capas--questionnaire-target="answerView"] p');
      const answerEdit = this.element.querySelector(`[data-answer-field="answer_${i}"]`);
      
      const questionValue = questionnaire[`question_${i}`] || '';
      const answerValue = questionnaire[`answer_${i}`] || '';
      
      if (questionView) questionView.textContent = questionValue;
      if (questionEdit) questionEdit.value = questionValue;
      if (answerView) answerView.textContent = answerValue;
      if (answerEdit) answerEdit.value = answerValue;
    }
    
    // Update root cause
    const rootCauseView = this.element.querySelector('[data-capas--questionnaire-target="rootCauseView"]');
    const rootCauseEdit = this.element.querySelector('[data-capas--questionnaire-target="rootCauseEdit"]');
    const rootCauseValue = questionnaire.root_cause || '';
    
    if (rootCauseView) rootCauseView.textContent = rootCauseValue;
    if (rootCauseEdit) rootCauseEdit.value = rootCauseValue;
  }

  showSuccess(message) {
    if (!message) return;
    this.dispatchToast(message, 'success');
  }

  showError(message) {
    if (!message) return;
    this.dispatchToast(message, 'error');
  }

  dispatchToast(notificationHtmlOrMessage, type = 'success') {
    let notificationHtml = notificationHtmlOrMessage;
    
    // If it's a plain message string, create notification HTML
    if (!notificationHtmlOrMessage || (typeof notificationHtmlOrMessage === 'string' && !notificationHtmlOrMessage.includes('data-toast-target'))) {
      const bgColor = type === 'success' 
        ? 'bg-[#FFFFFF] border-[#E3E3E3] border-l-4 border-l-[#5C3984]'
        : 'bg-[#FFFFFF] border-[#E3E3E3] border-l-4 border-l-red-500';
      
      const icon = type === 'success'
        ? '<svg class="w-5 h-5 text-[#5C3984]" fill="currentColor" viewBox="0 0 20 20"><path fill-rule="evenodd" d="M10 18a8 8 0 100-16 8 8 0 000 16zm3.707-9.293a1 1 0 00-1.414-1.414L9 10.586 7.707 9.293a1 1 0 00-1.414 1.414l2 2a1 1 0 001.414 0l4-4z" clip-rule="evenodd"/></svg>'
        : '<svg class="w-5 h-5 text-red-500" fill="currentColor" viewBox="0 0 20 20"><path fill-rule="evenodd" d="M10 18a8 8 0 100-16 8 8 0 000 16zM8.707 7.293a1 1 0 00-1.414 1.414L8.586 10l-1.293 1.293a1 1 0 101.414 1.414L10 11.414l1.293 1.293a1 1 0 001.414-1.414L11.414 10l1.293-1.293a1 1 0 00-1.414-1.414L10 8.586 8.707 7.293z" clip-rule="evenodd"/></svg>';

      notificationHtml = `
        <div 
          data-toast-target="notification"
          class="${bgColor} rounded-lg shadow-lg p-4 flex items-start gap-3 transform opacity-0 translate-x-full transition ease-out duration-300"
        >
          ${icon}
          <div class="flex-1 text-sm text-[#0D1120] font-medium">
            ${notificationHtmlOrMessage || 'Operation completed'}
          </div>
          <button 
            data-action="click->toast#close"
            class="text-gray-400 hover:text-gray-600 transition-colors"
          >
            <svg class="w-5 h-5" fill="currentColor" viewBox="0 0 20 20">
              <path fill-rule="evenodd" d="M4.293 4.293a1 1 0 011.414 0L10 8.586l4.293-4.293a1 1 0 111.414 1.414L11.414 10l4.293 4.293a1 1 0 01-1.414 1.414L10 11.414l-4.293 4.293a1 1 0 01-1.414-1.414L8.586 10 4.293 5.707a1 1 0 010-1.414z" clip-rule="evenodd"/>
            </svg>
          </button>
        </div>
      `;
    }

    // Dispatch custom event for toast controller to handle
    const event = new CustomEvent('toast:show', {
      detail: { notificationHtml },
      bubbles: true
    });
    document.dispatchEvent(event);
  }
}

