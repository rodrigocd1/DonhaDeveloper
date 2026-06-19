import { LightningElement, api } from "lwc";

export default class PesquisasIdentificacao extends LightningElement {
  cpf = "";
  email = "";
  telefone = "";

  handleChange(event) {
    this[event.target.dataset.field] = event.detail.value;
    this.clearIdentityError();
  }

  @api
  getValue() {
    return {
      cpf: this.cpf,
      email: this.email,
      telefone: this.telefone
    };
  }

  @api
  reportValidity() {
    const inputs = [...this.template.querySelectorAll("lightning-input")];
    const hasIdentity = [this.cpf, this.email, this.telefone].some((value) =>
      value?.trim()
    );
    inputs[0]?.setCustomValidity(
      hasIdentity ? "" : "Informe CPF, e-mail ou telefone."
    );
    return inputs.every((input) => input.reportValidity()) && hasIdentity;
  }

  clearIdentityError() {
    const cpfInput = this.template.querySelector('[data-field="cpf"]');
    cpfInput?.setCustomValidity("");
  }
}
