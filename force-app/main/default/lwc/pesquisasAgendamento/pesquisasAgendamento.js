import { LightningElement, api } from "lwc";
import criarAgendamento from "@salesforce/apex/PesquisasPortalController.criarAgendamento";

export default class PesquisasAgendamento extends LightningElement {
  @api empreendimentoOptions = [];
  formData = {};
  errorMessage;
  isSubmitting = false;

  periodoOptions = [
    { label: "Manhã", value: "Manhã" },
    { label: "Tarde", value: "Tarde" }
  ];

  get comboboxOptions() {
    return this.empreendimentoOptions.map((item) => ({
      label: [item.nome, item.bairro, item.regiao].filter(Boolean).join(" — "),
      value: item.id
    }));
  }

  get minDate() {
    const now = new Date();
    const local = new Date(now.getTime() - now.getTimezoneOffset() * 60000);
    return local.toISOString().split("T")[0];
  }

  get submitLabel() {
    return this.isSubmitting ? "Enviando..." : "Confirmar agendamento";
  }

  handleChange(event) {
    this.formData = {
      ...this.formData,
      [event.target.dataset.field]: event.detail.value
    };
    this.errorMessage = undefined;
  }

  async handleSubmit(event) {
    event.preventDefault();
    if (this.isSubmitting || !this.validateForm()) {
      return;
    }
    this.isSubmitting = true;
    this.errorMessage = undefined;
    try {
      const identificacao = this.template
        .querySelector("c-pesquisas-identificacao")
        .getValue();
      const result = await criarAgendamento({
        input: { ...this.formData, ...identificacao }
      });
      this.dispatchEvent(
        new CustomEvent("sucesso", { detail: result.mensagem })
      );
    } catch (error) {
      this.errorMessage =
        error?.body?.message || "Não foi possível registrar o agendamento.";
    } finally {
      this.isSubmitting = false;
    }
  }

  validateForm() {
    const identityValid = this.template
      .querySelector("c-pesquisas-identificacao")
      .reportValidity();
    const fields = [
      ...this.template.querySelectorAll(
        "lightning-input, lightning-combobox, lightning-textarea"
      )
    ];
    return fields.every((field) => field.reportValidity()) && identityValid;
  }

  handleBack() {
    this.dispatchEvent(new CustomEvent("voltar"));
  }
}
