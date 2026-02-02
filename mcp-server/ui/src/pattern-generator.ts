import { App } from "@modelcontextprotocol/ext-apps";

const app = new App({ name: "Infrastructure Pattern Generator", version: "1.0.0" });

interface PatternResult {
  pattern: string;
  project: string;
  environment: string;
  yaml: string;
}

// Initialize the app
async function init() {
  const appEl = document.getElementById("app")!;

  try {
    // Connect to the host (Claude)
    await app.connect();

    // Render the form
    appEl.innerHTML = `
      <h1>🏗️ Infrastructure Pattern Generator</h1>
      <p class="subtitle">Generate infrastructure configuration for your project</p>

      <form id="pattern-form">
        <div class="form-group">
          <label for="project">Project Name *</label>
          <input type="text" id="project" required placeholder="myapp">
          <small>Lowercase, alphanumeric, hyphens allowed</small>
        </div>

        <div class="form-group">
          <label for="pattern">Pattern *</label>
          <select id="pattern" required>
            <option value="">Select a pattern...</option>
            <option value="keyvault">Key Vault - Secure secrets storage</option>
            <option value="postgresql">PostgreSQL - Managed database</option>
            <option value="storage">Storage Account - Blob storage</option>
            <option value="function-app">Function App - Serverless compute</option>
            <option value="static-site">Static Web App - SPA hosting</option>
            <option value="web-app">Web App - Full stack (SWA + Functions + DB)</option>
          </select>
        </div>

        <div class="form-group">
          <label for="name">Resource Name *</label>
          <input type="text" id="name" required placeholder="api">
          <small>Name for this specific resource</small>
        </div>

        <div class="form-group">
          <label for="environment">Environment *</label>
          <select id="environment" required>
            <option value="dev">Development</option>
            <option value="staging">Staging</option>
            <option value="prod">Production</option>
          </select>
        </div>

        <div class="form-group">
          <label for="business-unit">Business Unit *</label>
          <input type="text" id="business-unit" required placeholder="engineering">
        </div>

        <div class="form-group">
          <label for="owners">Owners (email addresses) *</label>
          <textarea id="owners" required placeholder="alice@company.com&#10;bob@company.com" rows="3"></textarea>
          <small>One email per line</small>
        </div>

        <div class="form-group">
          <label for="location">Azure Region *</label>
          <select id="location" required>
            <option value="eastus">East US</option>
            <option value="westus">West US</option>
            <option value="centralus">Central US</option>
          </select>
        </div>

        <button type="submit">Generate Configuration</button>
      </form>

      <div id="status"></div>
    `;

    // Handle form submission
    const form = document.getElementById("pattern-form") as HTMLFormElement;
    form.addEventListener("submit", async (e) => {
      e.preventDefault();
      await generatePattern(form);
    });

  } catch (error) {
    appEl.innerHTML = `
      <div class="status error">
        <strong>Error:</strong> Failed to initialize app. ${error}
      </div>
    `;
  }
}

async function generatePattern(form: HTMLFormElement) {
  const statusEl = document.getElementById("status")!;
  const submitBtn = form.querySelector("button[type=submit]") as HTMLButtonElement;

  try {
    submitBtn.disabled = true;
    submitBtn.textContent = "Generating...";
    statusEl.innerHTML = "";

    // Collect form data
    const formData = new FormData(form);
    const project = (document.getElementById("project") as HTMLInputElement).value;
    const pattern = (document.getElementById("pattern") as HTMLSelectElement).value;
    const name = (document.getElementById("name") as HTMLInputElement).value;
    const environment = (document.getElementById("environment") as HTMLSelectElement).value;
    const businessUnit = (document.getElementById("business-unit") as HTMLInputElement).value;
    const ownersText = (document.getElementById("owners") as HTMLTextAreaElement).value;
    const location = (document.getElementById("location") as HTMLSelectElement).value;

    const owners = ownersText.split("\n").map(e => e.trim()).filter(e => e);

    // Call the MCP server tool to generate the pattern
    const result = await app.callServerTool({
      name: "generate_pattern_request",
      arguments: {
        pattern,
        project_name: project,
        environment,
        business_unit: businessUnit,
        owners,
        location,
        config: { name }
      }
    });

    // Extract the YAML from the result
    const yaml = result.content?.find((c: any) => c.type === "text")?.text || "";

    // Show success message
    statusEl.innerHTML = `
      <div class="status success">
        <strong>✓ Configuration generated!</strong><br>
        The infrastructure.yaml has been added to the conversation.
      </div>
    `;

    // Update the model context with the generated YAML
    await app.sendMessage({
      role: "user",
      content: {
        type: "text",
        text: `Here is the generated infrastructure configuration:\n\n\`\`\`yaml\n${yaml}\n\`\`\``
      }
    });

    // Reset form
    form.reset();

  } catch (error: any) {
    statusEl.innerHTML = `
      <div class="status error">
        <strong>Error:</strong> ${error.message || "Failed to generate configuration"}
      </div>
    `;
  } finally {
    submitBtn.disabled = false;
    submitBtn.textContent = "Generate Configuration";
  }
}

// Start the app when the page loads
init();
