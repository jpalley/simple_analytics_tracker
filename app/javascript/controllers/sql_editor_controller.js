import { Controller } from "@hotwired/stimulus"
import CodeMirror from "codemirror"
import "codemirror/mode/sql/sql"
import "codemirror/addon/edit/matchbrackets"
import "codemirror/addon/edit/closebrackets"
import "codemirror/addon/display/placeholder"

// Connects to data-controller="sql-editor"
export default class extends Controller {
  static targets = ["textarea"]
  static values = {
    theme: { type: String, default: "default" }
  }

  connect() {
    console.log("SQL Editor controller connected", this.element)
    console.log("Textarea target found:", this.hasTextareaTarget)
    
    if (this.hasTextareaTarget) {
      console.log("CodeMirror available:", typeof CodeMirror)
      
      // Load CodeMirror CSS
      this.loadStyles()
      
      try {
        // Initialize CodeMirror
        this.editor = CodeMirror.fromTextArea(this.textareaTarget, {
          mode: 'text/x-sql',
          theme: this.themeValue,
          lineNumbers: true,
          indentWithTabs: false,
          tabSize: 2,
          indentUnit: 2,
          lineWrapping: true,
          matchBrackets: true,
          autoCloseBrackets: true,
          placeholder: this.textareaTarget.placeholder,
          extraKeys: {
            'Ctrl-Enter': (cm) => {
              // Submit the form when Ctrl+Enter is pressed
              this.textareaTarget.form.requestSubmit()
            },
            'Cmd-Enter': (cm) => {
              // Submit the form when Cmd+Enter is pressed (for Mac)
              this.textareaTarget.form.requestSubmit()
            },
            'Tab': (cm) => {
              // Insert spaces instead of tab character
              const spaces = Array(cm.getOption("indentUnit") + 1).join(" ")
              cm.replaceSelection(spaces)
            }
          }
        })
        console.log("CodeMirror editor initialized successfully")
        
        // Sync CodeMirror with textarea before form submission
        this.textareaTarget.form.addEventListener('submit', () => {
          this.editor.save()
        })
      } catch (error) {
        console.error("Error initializing CodeMirror:", error)
      }
    }
  }
  
  disconnect() {
    if (this.editor) {
      // Clean up CodeMirror instance
      try {
        this.editor.toTextArea()
      } catch (error) {
        console.error("Error cleaning up CodeMirror:", error)
      }
    }
  }
  
  loadStyles() {
    // Only load styles once
    if (document.querySelector('#codemirror-styles')) return
    
    try {
      const styles = document.createElement('link')
      styles.id = 'codemirror-styles'
      styles.rel = 'stylesheet'
      styles.href = 'https://unpkg.com/codemirror@5.65.13/lib/codemirror.css'
      document.head.appendChild(styles)
      console.log("CodeMirror base styles loaded")
      
      // Add theme if not default
      if (this.themeValue !== 'default') {
        const themeStyles = document.createElement('link')
        themeStyles.id = 'codemirror-theme-styles'
        themeStyles.rel = 'stylesheet'
        themeStyles.href = `https://unpkg.com/codemirror@5.65.13/theme/${this.themeValue}.css`
        document.head.appendChild(themeStyles)
        console.log(`CodeMirror theme ${this.themeValue} styles loaded`)
      }
      
      // Add custom styles
      const customStyles = document.createElement('style')
      customStyles.textContent = `
        .CodeMirror {
          height: auto;
          min-height: 150px;
          border: 1px solid #dee2e6;
          border-radius: 0.25rem;
          font-family: SFMono-Regular, Menlo, Monaco, Consolas, "Liberation Mono", "Courier New", monospace;
          font-size: 14px;
        }
        
        .CodeMirror-focused {
          border-color: #86b7fe;
          outline: 0;
          box-shadow: 0 0 0 0.25rem rgb(13 110 253 / 25%);
        }
        
        .cm-s-monokai.CodeMirror { background: #272822; color: #f8f8f2; }
        .cm-s-monokai .CodeMirror-gutters { background: #272822; border-right: 0px; }
        .cm-s-monokai .CodeMirror-guttermarker { color: white; }
        .cm-s-monokai .CodeMirror-guttermarker-subtle { color: #d0d0d0; }
        .cm-s-monokai .CodeMirror-linenumber { color: #d0d0d0; }
        .cm-s-monokai .CodeMirror-cursor { border-left: 1px solid #f8f8f0; }
      `
      document.head.appendChild(customStyles)
      console.log("CodeMirror custom styles loaded")
    } catch (error) {
      console.error("Error loading CodeMirror styles:", error)
    }
  }
} 