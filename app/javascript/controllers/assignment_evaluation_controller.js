import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["modal", "form", "scoreSlider", "scoreInput", "scoreDisplay", "percentageDisplay", "percentageInput", "feedbackInput", "commentsInput", "approveRadio", "rejectRadio", "multipleChoiceRadio"]
  static values = {
    assignmentId: String,
    scoringType: String,
    minScore: Number,
    maxScore: Number
  }

  connect() {
    // Close modal when clicking outside
    this.boundHandleClickOutside = this.handleClickOutside.bind(this)
    if (this.hasModalTarget) {
      this.modalTarget.addEventListener("click", this.boundHandleClickOutside)
    }
    
    // Find and connect the evaluate button
    const evaluateBtn = document.getElementById('evaluate-btn')
    if (evaluateBtn) {
      evaluateBtn.addEventListener('click', () => this.open())
    }
  }

  disconnect() {
    if (this.hasModalTarget) {
      this.modalTarget.removeEventListener("click", this.boundHandleClickOutside)
    }
  }

  open(event) {
    if (this.hasModalTarget) {
      this.modalTarget.showModal()
      this.initializeForm()
    }
  }

  close() {
    if (this.hasModalTarget) {
      this.modalTarget.close()
    }
  }

  handleClickOutside(event) {
    if (event.target === this.modalTarget) {
      this.close()
    }
  }

  initializeForm() {
    // Initialize score slider based on scoring type
    if (this.scoringTypeValue === "Percentage" || this.scoringTypeValue === "Number") {
      if (this.hasScoreSliderTarget) {
        const currentValue = parseFloat(this.scoreSliderTarget.value) || (this.scoringTypeValue === "Percentage" ? 50 : (this.minScoreValue || 0))
        this.updateScoreDisplay(currentValue)
        this.updateSliderProgress(this.scoreSliderTarget)
        
        // Initialize percentage display
        const minScore = parseFloat(this.scoreSliderTarget.dataset.minScore) || 0
        const maxScore = parseFloat(this.scoreSliderTarget.dataset.maxScore) || 100
        const percentage = maxScore > minScore ? ((currentValue - minScore) / (maxScore - minScore)) * 100 : 0
        const roundedPercentage = Math.round(percentage * 10) / 10
        
        if (this.hasPercentageDisplayTarget) {
          this.percentageDisplayTarget.textContent = `${roundedPercentage}%`
        }
        if (this.hasPercentageInputTarget) {
          this.percentageInputTarget.value = roundedPercentage
        }
      }
    }

    // Note: Don't reset form if there's existing evaluation data (it will be pre-filled)
  }

  updateScore(event) {
    const value = parseFloat(event.target.value) || 0
    this.updateScoreDisplay(value)
    this.updateSliderProgress(event.target)
  }

  updatePercentage(event) {
    const score = parseFloat(event.target.value) || 0
    const minScore = parseFloat(event.target.dataset.minScore) || 0
    const maxScore = parseFloat(event.target.dataset.maxScore) || 100
    
    // Calculate percentage: ((score - min) / (max - min)) * 100
    const percentage = maxScore > minScore ? ((score - minScore) / (maxScore - minScore)) * 100 : 0
    const roundedPercentage = Math.round(percentage * 10) / 10 // Round to 1 decimal place
    
    // Update percentage display
    if (this.hasPercentageDisplayTarget) {
      this.percentageDisplayTarget.textContent = `${roundedPercentage}%`
    }
    
    // Update hidden percentage input
    if (this.hasPercentageInputTarget) {
      this.percentageInputTarget.value = roundedPercentage
    }
  }

  updateMultipleChoiceScore(event) {
    const selectedRadio = event.target
    const optionWeight = parseFloat(selectedRadio.dataset.optionWeight) || parseFloat(selectedRadio.value) || 0
    const optionText = selectedRadio.dataset.optionText
    
    // Update score display with the selected option's text
    if (this.hasScoreDisplayTarget) {
      this.scoreDisplayTarget.textContent = optionText || `${optionWeight}%`
    }
    
    // Use the weight directly as the percentage
    const roundedPercentage = Math.round(optionWeight * 10) / 10
    
    // Update percentage display
    if (this.hasPercentageDisplayTarget) {
      this.percentageDisplayTarget.textContent = `${roundedPercentage}%`
    }
    
    // Update hidden percentage input
    if (this.hasPercentageInputTarget) {
      this.percentageInputTarget.value = roundedPercentage
    }
  }

  updateSliderProgress(slider) {
    const min = parseFloat(slider.min) || 0
    const max = parseFloat(slider.max) || 100
    const value = parseFloat(slider.value) || 0
    const percentage = ((value - min) / (max - min)) * 100
    slider.style.setProperty('--slider-progress', `${percentage}%`)
  }

  updateScoreDisplay(value) {
    const roundedValue = Math.round(value)
    if (this.hasScoreDisplayTarget) {
      if (this.scoringTypeValue === "Percentage") {
        this.scoreDisplayTarget.textContent = `${roundedValue}%`
      } else {
        this.scoreDisplayTarget.textContent = roundedValue
      }
    }
    // Update hidden input for form submission
    const hiddenInput = this.formTarget.querySelector('input[name="assignment_evaluation[score]"]')
    if (hiddenInput) {
      hiddenInput.value = roundedValue
    }
  }

  submit(event) {
    event.preventDefault()
    
    // Validate that evaluation status is selected
    const evaluationStatus = this.formTarget.querySelector('input[name="assignment_evaluation[evaluation_status]"]:checked')

    // Validate score if scoring type requires it
    if (this.scoringTypeValue) {
      if (this.scoringTypeValue === "Multiple Choice") {
        // Validate multiple choice selection
        const selectedOption = this.formTarget.querySelector('input[name="assignment_evaluation[score]"]:checked')
        if (!selectedOption) {
          alert("Please select one of the options")
          return false
        }
      } else if (this.scoringTypeValue === "Number" || this.scoringTypeValue === "Percentage") {
        // Validate number/percentage score
        const hiddenInput = this.formTarget.querySelector('input[name="assignment_evaluation[score]"]')
        const score = hiddenInput ? parseFloat(hiddenInput.value) : null
        
        if (score === null || isNaN(score)) {
          alert("Please enter a valid score")
          return false
        }
        
        // Validate score range
        if (this.minScoreValue !== null && score < this.minScoreValue) {
          alert(`Score must be at least ${this.minScoreValue}`)
          return false
        }
        if (this.maxScoreValue !== null && score > this.maxScoreValue) {
          alert(`Score must be at most ${this.maxScoreValue}`)
          return false
        }
      }
    }

    // Validate feedback length
    if (this.hasFeedbackInputTarget) {
      const feedback = this.feedbackInputTarget.value
      if (feedback.length > 300) {
        alert("Feedback must be 300 characters or less")
        return false
      }
    }

    // Submit the form
    this.formTarget.submit()
  }
}

