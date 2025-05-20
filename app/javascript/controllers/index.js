// Import and register all your controllers from the importmap via controllers/**/*_controller
import { application } from "./application"
import { eagerLoadControllersFrom } from "@hotwired/stimulus-loading"
eagerLoadControllersFrom("controllers", application)

console.log("Application controllers:", application.controllers)
import SqlEditorController from "./sql_editor_controller"
application.register("sql-editor", SqlEditorController)