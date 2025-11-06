#!/usr/bin/env python3
"""
convert_translation_model.py
OPUS-MT to CoreML Model Converter for SWORDCOMM Translation

This script automates the conversion of OPUS-MT models to CoreML format:
1. Downloads OPUS-MT model from Hugging Face
2. Converts to CoreML format
3. Quantizes to INT8 (reduces size by ~75%)
4. Validates the converted model
5. Outputs ready-to-use .mlmodel file

Usage:
    python3 convert_translation_model.py [--source da] [--target en] [--quantize] [--validate]

Requirements:
    pip install transformers torch coremltools sentencepiece
"""

import argparse
import os
import sys
from pathlib import Path

# Colors for terminal output
class Colors:
    BLUE = '\033[0;34m'
    GREEN = '\033[0;32m'
    YELLOW = '\033[1;33m'
    RED = '\033[0;31m'
    NC = '\033[0m'

def log_info(msg):
    print(f"{Colors.BLUE}[INFO]{Colors.NC} {msg}")

def log_success(msg):
    print(f"{Colors.GREEN}[SUCCESS]{Colors.NC} {msg}")

def log_warning(msg):
    print(f"{Colors.YELLOW}[WARNING]{Colors.NC} {msg}")

def log_error(msg):
    print(f"{Colors.RED}[ERROR]{Colors.NC} {msg}")

def check_dependencies():
    """Check if required Python packages are installed"""
    log_info("Checking dependencies...")

    required_packages = {
        'transformers': 'transformers',
        'torch': 'torch',
        'coremltools': 'coremltools',
        'sentencepiece': 'sentencepiece'
    }

    missing = []
    for package_import, package_name in required_packages.items():
        try:
            __import__(package_import)
            log_success(f"  ✓ {package_name} installed")
        except ImportError:
            log_error(f"  ✗ {package_name} not found")
            missing.append(package_name)

    if missing:
        log_error(f"Missing packages: {', '.join(missing)}")
        log_info(f"Install with: pip install {' '.join(missing)}")
        return False

    log_success("All dependencies installed")
    return True

def download_opus_mt_model(source_lang, target_lang, output_dir):
    """Download OPUS-MT model from Hugging Face"""
    log_info(f"Downloading OPUS-MT model ({source_lang} → {target_lang})...")

    from transformers import MarianMTModel, MarianTokenizer

    model_name = f"Helsinki-NLP/opus-mt-{source_lang}-{target_lang}"

    try:
        log_info(f"  Downloading from: {model_name}")
        tokenizer = MarianTokenizer.from_pretrained(model_name)
        model = MarianMTModel.from_pretrained(model_name)

        # Save to output directory
        model_dir = os.path.join(output_dir, "opus-mt-model")
        os.makedirs(model_dir, exist_ok=True)

        tokenizer.save_pretrained(model_dir)
        model.save_pretrained(model_dir)

        log_success(f"Model downloaded to: {model_dir}")
        return model, tokenizer, model_dir

    except Exception as e:
        log_error(f"Failed to download model: {e}")
        return None, None, None

def convert_to_coreml(model, tokenizer, model_dir, output_path, quantize=False):
    """Convert PyTorch model to CoreML format"""
    log_info("Converting model to CoreML format...")

    import torch
    import coremltools as ct

    try:
        # Set model to evaluation mode
        model.eval()

        # Create example input
        example_text = "Hej, hvordan har du det?"
        log_info(f"  Using example text: '{example_text}'")

        inputs = tokenizer(example_text, return_tensors="pt", padding=True)
        input_ids = inputs["input_ids"]
        attention_mask = inputs["attention_mask"]

        log_info(f"  Input shape: {input_ids.shape}")

        # Trace the model
        log_info("  Tracing model...")
        with torch.no_grad():
            traced_model = torch.jit.trace(
                model,
                (input_ids, attention_mask)
            )

        # Convert to CoreML
        log_info("  Converting to CoreML...")

        # Define input shapes
        input_shape = ct.Shape(shape=(1, ct.RangeDim(1, 512)))  # Variable sequence length

        mlmodel = ct.convert(
            traced_model,
            inputs=[
                ct.TensorType(name="input_ids", shape=input_shape, dtype=int),
                ct.TensorType(name="attention_mask", shape=input_shape, dtype=int)
            ],
            outputs=[
                ct.TensorType(name="output")
            ],
            minimum_deployment_target=ct.target.iOS15,
            compute_units=ct.ComputeUnit.ALL  # Use Neural Engine when available
        )

        # Add metadata
        mlmodel.author = "SWORDCOMM Translation Kit"
        mlmodel.short_description = f"OPUS-MT translation model ({source_lang} → {target_lang})"
        mlmodel.version = "1.0.0"

        # Quantize if requested
        if quantize:
            log_info("  Quantizing model to INT8...")
            mlmodel = ct.models.neural_network.quantization_utils.quantize_weights(
                mlmodel,
                nbits=8
            )
            log_success("  Model quantized (expect ~75% size reduction)")

        # Save model
        log_info(f"  Saving to: {output_path}")
        mlmodel.save(output_path)

        # Get file size
        size_mb = os.path.getsize(output_path) / (1024 * 1024)
        log_success(f"CoreML model saved: {size_mb:.1f} MB")

        return mlmodel

    except Exception as e:
        log_error(f"Failed to convert model: {e}")
        import traceback
        traceback.print_exc()
        return None

def validate_model(model_path, tokenizer):
    """Validate the CoreML model with test translations"""
    log_info("Validating CoreML model...")

    import coremltools as ct

    try:
        # Load CoreML model
        mlmodel = ct.models.MLModel(model_path)

        log_info("  Model loaded successfully")

        # Test translations
        test_sentences = [
            "Hej, hvordan har du det?",
            "Jeg elsker at rejse.",
            "Hvad laver du i dag?"
        ]

        log_info("  Running test translations...")

        for sentence in test_sentences:
            # Tokenize
            inputs = tokenizer(sentence, return_tensors="pt", padding=True)
            input_ids = inputs["input_ids"].numpy()
            attention_mask = inputs["attention_mask"].numpy()

            # Run prediction
            prediction = mlmodel.predict({
                "input_ids": input_ids,
                "attention_mask": attention_mask
            })

            log_success(f"  ✓ Translated: '{sentence}'")

        log_success("Model validation passed")
        return True

    except Exception as e:
        log_error(f"Validation failed: {e}")
        return False

def create_tokenizer_files(tokenizer, output_dir):
    """Create SentencePiece tokenizer files for Swift"""
    log_info("Creating tokenizer files for Swift integration...")

    try:
        tokenizer_dir = os.path.join(output_dir, "tokenizer")
        os.makedirs(tokenizer_dir, exist_ok=True)

        # Save SentencePiece model
        sp_model_path = os.path.join(tokenizer_dir, "source.spm")

        # Copy SentencePiece model from tokenizer
        import shutil
        tokenizer_files = Path(tokenizer.name_or_path)

        source_spm = tokenizer_files / "source.spm"
        if source_spm.exists():
            shutil.copy(source_spm, sp_model_path)
            log_success(f"  Tokenizer saved: {sp_model_path}")
        else:
            log_warning("  SentencePiece model not found")

        # Save vocabulary
        vocab_path = os.path.join(tokenizer_dir, "vocab.json")
        vocab = tokenizer.get_vocab()

        import json
        with open(vocab_path, 'w', encoding='utf-8') as f:
            json.dump(vocab, f, ensure_ascii=False, indent=2)

        log_success(f"  Vocabulary saved: {vocab_path}")

        return True

    except Exception as e:
        log_error(f"Failed to create tokenizer files: {e}")
        return False

def print_integration_instructions(model_path, source_lang, target_lang):
    """Print instructions for integrating the model into SWORDCOMM"""
    print()
    print("━" * 70)
    print(f"{Colors.GREEN}CoreML Model Conversion Complete!{Colors.NC}")
    print("━" * 70)
    print()
    print(f"Model location: {model_path}")
    print()
    print("Next Steps:")
    print()
    print("1. Add model to Xcode project:")
    print("   - Drag SWORDCOMMTranslation.mlmodel into Xcode")
    print("   - Add to Signal target")
    print("   - Ensure 'Copy items if needed' is checked")
    print()
    print("2. Verify model in project:")
    print("   - Click on .mlmodel file in Xcode")
    print("   - Check 'Model Class' is generated")
    print("   - Note input/output names")
    print()
    print("3. Update EMTranslationEngine.swift:")
    print("   - Update model loading code")
    print("   - Update input/output handling")
    print("   - Test translation with sample text")
    print()
    print("4. Test translations:")
    print(f"   - Source language: {source_lang}")
    print(f"   - Target language: {target_lang}")
    print("   - Try: 'Hej, hvordan har du det?' → 'Hi, how are you?'")
    print()
    print("5. Monitor performance:")
    print("   - Check inference time (should be < 100ms)")
    print("   - Verify Neural Engine usage")
    print("   - Test on device (not just simulator)")
    print()
    print("For detailed instructions, see:")
    print("  - SWORDCOMM/COREML_TRANSLATION_GUIDE.md")
    print("  - SWORDCOMM/TranslationKit/EMTranslationEngine.swift")
    print()
    print("━" * 70)

def main():
    parser = argparse.ArgumentParser(
        description="Convert OPUS-MT model to CoreML format for SWORDCOMM"
    )
    parser.add_argument(
        "--source",
        default="da",
        help="Source language code (default: da for Danish)"
    )
    parser.add_argument(
        "--target",
        default="en",
        help="Target language code (default: en for English)"
    )
    parser.add_argument(
        "--quantize",
        action="store_true",
        help="Quantize model to INT8 (reduces size by ~75%%)"
    )
    parser.add_argument(
        "--validate",
        action="store_true",
        help="Validate model after conversion"
    )
    parser.add_argument(
        "--output",
        help="Output directory (default: SWORDCOMM/TranslationKit/Models)"
    )

    args = parser.parse_args()

    # Determine output directory
    script_dir = Path(__file__).parent
    project_root = script_dir.parent.parent

    if args.output:
        output_dir = Path(args.output)
    else:
        output_dir = project_root / "SWORDCOMM" / "TranslationKit" / "Models"

    output_dir.mkdir(parents=True, exist_ok=True)

    print()
    print("━" * 70)
    print("  OPUS-MT to CoreML Model Converter")
    print(f"  Translation: {args.source} → {args.target}")
    print(f"  Quantization: {'Enabled' if args.quantize else 'Disabled'}")
    print("━" * 70)
    print()

    # Check dependencies
    if not check_dependencies():
        sys.exit(1)
    print()

    # Download model
    model, tokenizer, model_dir = download_opus_mt_model(
        args.source,
        args.target,
        str(output_dir)
    )

    if model is None:
        log_error("Failed to download model")
        sys.exit(1)
    print()

    # Convert to CoreML
    model_name = f"SWORDCOMMTranslation_{args.source}_{args.target}"
    if args.quantize:
        model_name += "_int8"
    model_name += ".mlmodel"

    model_path = output_dir / model_name

    mlmodel = convert_to_coreml(
        model,
        tokenizer,
        model_dir,
        str(model_path),
        quantize=args.quantize
    )

    if mlmodel is None:
        log_error("Failed to convert model")
        sys.exit(1)
    print()

    # Create tokenizer files
    create_tokenizer_files(tokenizer, str(output_dir))
    print()

    # Validate if requested
    if args.validate:
        if not validate_model(str(model_path), tokenizer):
            log_warning("Validation failed, but model was created")
        print()

    # Print integration instructions
    print_integration_instructions(str(model_path), args.source, args.target)

if __name__ == "__main__":
    main()
