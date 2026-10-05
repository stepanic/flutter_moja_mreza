package com.example.flutter_moja_mreza

import android.app.Activity
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler

/** Most prema [MojaMrezaSesija]; ugovor je `lib/flutter_moja_mreza_platform_interface.dart`. */
class FlutterMojaMrezaPlugin : FlutterPlugin, MethodCallHandler, ActivityAware {
  private lateinit var channel: MethodChannel
  private var activity: Activity? = null
  private var sesija: MojaMrezaSesija? = null

  override fun onAttachedToEngine(flutterPluginBinding: FlutterPlugin.FlutterPluginBinding) {
    channel = MethodChannel(flutterPluginBinding.binaryMessenger, "flutter_moja_mreza")
    channel.setMethodCallHandler(this)
  }

  override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
    when (call.method) {
      "getPlatformVersion" -> result.success("Android ${android.os.Build.VERSION.RELEASE}")
      "prijava" -> {
        val a = activity ?: return result.error("mreza", "Plugin nije vezan uz Activity", null)
        sesija?.zatvori()
        val s = try {
          MojaMrezaSesija(a)
        } catch (e: MojaMrezaGreska) {
          return result.error(e.kod, e.message, null)
        }
        sesija = s
        s.prijava { odgovori(result, it) }
      }
      "dohvati" -> {
        val s = sesija ?: return result.error("otkazano", "Nema otvorene prijave", null)
        s.dohvati(call.argument<String>("putanja") ?: "/") { odgovori(result, it) }
      }
      "napredak" -> {
        sesija?.napredak(call.argument<String>("poruka") ?: "")
        result.success(null)
      }
      "zatvori" -> {
        sesija?.zatvori()
        sesija = null
        result.success(null)
      }
      "odjava" -> {
        val s = sesija
        sesija = null
        if (s == null) {
          MojaMrezaSesija.obrisiPodatke()
          result.success(null)
        } else {
          s.odjava { result.success(null) }
        }
      }
      else -> result.notImplemented()
    }
  }

  private fun <T> odgovori(result: MethodChannel.Result, r: Result<T>) {
    r.fold(
      { result.success(it) },
      {
        val kod = (it as? MojaMrezaGreska)?.kod ?: "mreza"
        result.error(kod, it.message, null)
      },
    )
  }

  override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
    channel.setMethodCallHandler(null)
  }

  override fun onAttachedToActivity(binding: ActivityPluginBinding) {
    activity = binding.activity
  }

  override fun onDetachedFromActivityForConfigChanges() {}

  override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) {
    activity = binding.activity
  }

  override fun onDetachedFromActivity() {
    sesija?.zatvori()
    sesija = null
    activity = null
  }
}
