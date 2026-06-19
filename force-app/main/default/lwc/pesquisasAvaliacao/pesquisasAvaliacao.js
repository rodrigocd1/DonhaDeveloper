import { LightningElement } from "lwc";
import registrarAvaliacao from "@salesforce/apex/PesquisasPortalController.registrarAvaliacao";

export default class PesquisasAvaliacao extends LightningElement {
  formData = {};
  rating = 0;
  ratingError = false;
  errorMessage;
  isSubmitting = false;

  handleChange(event) {
    this.formData = {
      ...this.formData,
      [event.target.dataset.field]: event.detail.value
    };
    this.errorMessage = undefined;
  }

  handleRating(event) {
    this.rating = Number(event.currentTarget.dataset.rating);
    this.ratingError = false;
  }

  async handleSubmit(event) {
    event.preventDefault();
    const fields = [
      ...this.template.querySelectorAll("lightning-input, lightning-textarea")
    ];
    const fieldsValid = fields.every((field) => field.reportValidity());
    this.ratingError = this.rating < 1;
    if (this.isSubmitting || !fieldsValid || this.ratingError) {
      return;
    }
    this.isSubmitting = true;
    this.errorMessage = undefined;
    try {
      const result = await registrarAvaliacao({
        input: { ...this.formData, nota: this.rating }
      });
      this.dispatchEvent(
        new CustomEvent("sucesso", { detail: result.mensagem })
      );
    } catch (error) {
      this.errorMessage =
        error?.body?.message || "Não foi possível registrar a avaliação.";
    } finally {
      this.isSubmitting = false;
    }
  }

  get submitLabel() {
    return this.isSubmitting ? "Enviando..." : "Enviar avaliação";
  }

  get starOneClass() {
    return this.starClass(1);
  }
  get starTwoClass() {
    return this.starClass(2);
  }
  get starThreeClass() {
    return this.starClass(3);
  }
  get starFourClass() {
    return this.starClass(4);
  }
  get starFiveClass() {
    return this.starClass(5);
  }
  get starOnePressed() {
    return this.rating === 1;
  }
  get starTwoPressed() {
    return this.rating === 2;
  }
  get starThreePressed() {
    return this.rating === 3;
  }
  get starFourPressed() {
    return this.rating === 4;
  }
  get starFivePressed() {
    return this.rating === 5;
  }

  starClass(position) {
    return this.rating >= position ? "star selected" : "star";
  }

  handleBack() {
    this.dispatchEvent(new CustomEvent("voltar"));
  }
}
