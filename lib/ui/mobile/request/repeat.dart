/*
 * Copyright 2023 Hongen Wang All rights reserved.
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *      https://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */
import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_toastr/flutter_toastr.dart';
import 'package:proxypin/l10n/app_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

///高级重放
/// @author wang
class MobileCustomRepeat extends StatefulWidget {
  final Function onRepeat;
  /// 并发发送：一次发起 count 条，返回成功条数
  final Future<int> Function(int count, bool waitResponse)? onRepeatBurst;
  /// 并发结束回调 (总条数, 成功条数, 耗时ms)
  final void Function(int total, int success, int elapsedMs)? onBurstDone;
  final SharedPreferences prefs;

  const MobileCustomRepeat(
      {super.key, required this.onRepeat, this.onRepeatBurst, this.onBurstDone, required this.prefs});

  @override
  State<StatefulWidget> createState() => _CustomRepeatState();
}

class _CustomRepeatState extends State<MobileCustomRepeat> {
  TextEditingController count = TextEditingController(text: '1');
  TextEditingController interval = TextEditingController(text: '0');
  TextEditingController minInterval = TextEditingController(text: '0');
  TextEditingController maxInterval = TextEditingController(text: '1000');
  TextEditingController delay = TextEditingController(text: '0');
  TextEditingController concurrency = TextEditingController(text: '1000');

  bool fixed = true;
  bool keepSetting = true;
  bool concurrent = false; // 并发模式：忽略间隔，瞬间发起
  bool waitResponse = true; // 是否等待响应并发回统计（关闭=只发不看，最快）

  DateTime? time;

  AppLocalizations get localizations => AppLocalizations.of(context)!;

  @override
  void initState() {
    super.initState();

    var customerRepeat = widget.prefs.getString('customerRepeat');
    keepSetting = customerRepeat != null;
    if (customerRepeat != null) {
      Map<String, dynamic> data = jsonDecode(customerRepeat);
      count.text = data['count'];
      interval.text = data['interval'];
      minInterval.text = data['minInterval'];
      maxInterval.text = data['maxInterval'];
      delay.text = data['delay'];
      fixed = data['fixed'] == true;
      concurrent = data['concurrent'] == true;
      waitResponse = data['waitResponse'] != false;
      if (data['concurrency'] != null) {
        concurrency.text = data['concurrency'];
      }
    }
  }

  @override
  void dispose() {
    count.dispose();
    interval.dispose();
    delay.dispose();
    concurrency.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final formKey = GlobalKey<FormState>();

    return Scaffold(
        appBar: AppBar(
          title: Text(localizations.customRepeat, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500)),
          actions: [
            TextButton(
              style: TextButton.styleFrom(foregroundColor: Colors.white),
              child: Text(localizations.done, style: const TextStyle(color: Colors.white, fontSize: 15)),
              onPressed: () {
                if (!formKey.currentState!.validate()) {
                  return;
                }
                if (keepSetting) {
                  widget.prefs.setString(
                      'customerRepeat',
                      jsonEncode({
                        'count': count.text,
                        'interval': interval.text,
                        'minInterval': minInterval.text,
                        'maxInterval': maxInterval.text,
                        'delay': delay.text,
                        'fixed': fixed,
                        'concurrent': concurrent,
                        'concurrency': concurrency.text,
                        'waitResponse': waitResponse
                      }));
                } else {
                  widget.prefs.remove('customerRepeat');
                }

                int delayValue = int.parse(delay.text);
                if (time != null) {
                  DateTime now = DateTime.now();
                  DateTime schedule = DateTime(now.year, now.month, now.day, time!.hour, time!.minute);
                  if (schedule.isBefore(now)) {
                    schedule = schedule.add(const Duration(days: 1));
                  }
                  delayValue += schedule.difference(now).inMilliseconds;
                }

                Future.delayed(Duration(milliseconds: delayValue), () {
                  if (concurrent) {
                    submitConcurrent(int.parse(count.text), int.tryParse(concurrency.text) ?? int.parse(count.text));
                  } else {
                    submitTask(int.parse(count.text));
                  }
                });
                Navigator.of(context).pop();
              },
            )
          ],
        ),
        body: SingleChildScrollView(
            padding: const EdgeInsets.all(15),
            child: Form(
              key: formKey,
              child: Column(
                children: <Widget>[
                  field(localizations.repeatCount, textField(count)), //次数
                  const SizedBox(height: 6),
                  concurrentWidget(), //并发模式
                  const SizedBox(height: 6),
                  intervalWidget(), //间隔
                  const SizedBox(height: 6),
                  field(localizations.repeatDelay, textField(delay)), //延时
                  const SizedBox(height: 6),
                  field(
                      localizations.scheduleTime,
                      InkWell(
                          onTap: _pickScheduleDateTime,
                          child: Container(
                            height: 42,
                            padding: const EdgeInsets.only(left: 10, right: 10),
                            decoration: BoxDecoration(
                                border: Border.all(
                                    color: Theme.of(context).colorScheme.primary.withAlpha((0.5 * 255).round()),
                                    width: 1.0),
                                borderRadius: BorderRadius.circular(4)),
                            child: Row(
                              children: [
                                Text(time == null
                                    ? ''
                                    : "${time!.year}-${_two(time!.month)}-${_two(time!.day)} ${_two(time!.hour)}:${_two(time!.minute)}"),
                                const Expanded(child: SizedBox()),
                                if (time != null)
                                  InkWell(
                                    onTap: () {
                                      setState(() {
                                        time = null;
                                      });
                                    },
                                    child: const Icon(Icons.clear, size: 18),
                                  ),
                                if (time == null)
                                  Icon(Icons.access_time, size: 18, color: Theme.of(context).colorScheme.primary),
                              ],
                            ),
                          ))), //指定时间
                  const SizedBox(height: 6),
                  //记录选择
                  Row(children: [
                    Text(localizations.keepCustomSettings),
                    Expanded(
                        child: Checkbox(
                            value: keepSetting,
                            onChanged: (val) {
                              setState(() {
                                keepSetting = val == true;
                              });
                            })),
                  ])
                ],
              ),
            )));
  }

  String _two(int v) => v.toString().padLeft(2, '0');

  //并发模式开关
  Widget concurrentWidget() {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      field(
          '并发模式',
          Transform.scale(
              scale: 0.82,
              child: CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  title: const Text('瞬间并发发送（压力测试）', style: TextStyle(fontSize: 13)),
                  value: concurrent,
                  onChanged: (val) => setState(() => concurrent = val == true)))),
      if (concurrent) ...[
        const SizedBox(height: 6),
        field('并发数', textField(concurrency, style: const TextStyle(fontSize: 13))),
        const SizedBox(height: 4),
        const Text('≥ 次数即一次性全发（不分批）；最大 1000',
            style: TextStyle(fontSize: 11, color: Colors.grey)),
        Transform.scale(
            scale: 0.82,
            child: CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                title: const Text('等待响应并统计结果', style: TextStyle(fontSize: 13)),
                value: waitResponse,
                onChanged: (val) => setState(() => waitResponse = val == true))),
        const Text('关闭=只发不看响应，发起最快（纯压力测试）；开启=结束后报告成功数与耗时',
            style: TextStyle(fontSize: 11, color: Colors.grey)),
      ],
    ]);
  }

  /// 并发重放：一次性把全部请求发出去，适合压力测试
  ///
  /// total —— 总条数；limit —— 同时在飞的上限（<=0 表示不限，一次性全发）
  /// 并发度超过 total 时按 total 发；否则分批发，每批 limit 条。
  Future<void> submitConcurrent(int total, int limit) async {
    final sw = Stopwatch()..start();
    int success = 0;

    final burst = widget.onRepeatBurst;
    if (burst == null) {
      // 未提供并发回调时退化为紧密循环（至少省掉 Future.delayed 的调度开销）
      for (int i = 0; i < total; i++) {
        widget.onRepeat.call();
      }
      sw.stop();
      widget.onBurstDone?.call(total, -1, sw.elapsedMilliseconds);
      return;
    }

    int remain = total;
    final wave = limit <= 0 ? total : limit;
    while (remain > 0) {
      var n = remain > wave ? wave : remain;
      if (n > 1000) n = 1000; // 单批上限，避免 fd 耗尽
      success += await burst(n, waitResponse);
      remain -= n;
    }

    sw.stop();
    widget.onBurstDone?.call(total, success, sw.elapsedMilliseconds);
  }

  //定时重放
  void submitTask(int counter) {
    if (counter <= 0) {
      return;
    }
    widget.onRepeat.call();

    int intervalValue = int.parse(interval.text);
    //随机
    if (!fixed) {
      int min = int.parse(minInterval.text);
      int max = int.parse(maxInterval.text);
      intervalValue = Random().nextInt(max - min) + min;
    }

    Future.delayed(Duration(milliseconds: intervalValue), () {
      if (counter - 1 > 0) {
        submitTask(counter - 1);
      }
    });
  }

  //间隔widget
  Widget intervalWidget() {
    return Row(
      children: [
        SizedBox(width: 83, child: Text(localizations.repeatInterval)),
        Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          //Checkbox样式 固定和随机
          Row(children: [
            SizedBox(
                width: 112,
                height: 35,
                child: Transform.scale(
                    scale: 0.82,
                    child: CheckboxListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text("${localizations.fixed}:"),
                        value: fixed,
                        dense: true,
                        onChanged: (val) {
                          setState(() {
                            fixed = true;
                          });
                        }))),
            Expanded(child: textField(interval, style: const TextStyle(fontSize: 13))),
          ]),
          const SizedBox(height: 5),
          Row(children: [
            SizedBox(
                width: 112,
                child: Transform.scale(
                    scale: 0.82,
                    child: CheckboxListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text("${localizations.random}:"),
                        value: !fixed,
                        dense: true,
                        onChanged: (val) {
                          setState(() {
                            fixed = false;
                          });
                        }))),
            Flexible(child: textField(minInterval, style: const TextStyle(fontSize: 13))),
            const Padding(padding: EdgeInsets.symmetric(horizontal: 5), child: Text("-")),
            Flexible(child: textField(maxInterval, style: const TextStyle(fontSize: 13))),
          ]),
        ])),
      ],
    );
  }


  Future<void> _pickScheduleDateTime() async {
    DateTime now = DateTime.now();
    DateTime temp = time ?? now;
    if (temp.isBefore(now)) {
      temp = now;
    }

    DateTime? selected = await showModalBottomSheet<DateTime>(
      context: context,
      builder: (BuildContext context) {
        DateTime current = temp;
        return SafeArea(
          child: SizedBox(
            height: 300,
            child: Column(
              children: [
                Expanded(
                  child: CupertinoDatePicker(
                    mode: CupertinoDatePickerMode.dateAndTime,
                    use24hFormat: true,
                    initialDateTime: temp,
                    minimumDate: now,
                    maximumDate: now.add(const Duration(days: 365)),
                    onDateTimeChanged: (DateTime value) {
                      current = value;
                    },
                  ),
                ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: Text(localizations.cancel),
                    ),
                    TextButton(
                      onPressed: () => Navigator.pop(context, current),
                      child: Text(localizations.done),
                    ),
                  ],
                )
              ],
            ),
          ),
        );
      },
    );

    if (selected != null) {
      setState(() {
        time = selected;
      });
    }
  }

  Widget field(String label, Widget child) {
    return Row(
      children: [
        SizedBox(width: 95, child: Text("$label :")),
        Expanded(child: child),
      ],
    );
  }

  FormField textField(TextEditingController? controller, {TextStyle? style}) {
    Color color = Theme.of(context).colorScheme.primary;

    return TextFormField(
      controller: controller,
      keyboardType: TextInputType.number,
      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
      style: style,
      decoration: InputDecoration(
          errorStyle: const TextStyle(height: 2, fontSize: 0),
          contentPadding: const EdgeInsets.only(left: 10, right: 10, top: 5, bottom: 5),
          border: OutlineInputBorder(borderSide: BorderSide(width: 1, color: color.withOpacity(0.3))),
          enabledBorder: OutlineInputBorder(borderSide: BorderSide(width: 1.5, color: color.withOpacity(0.5))),
          focusedBorder: OutlineInputBorder(borderSide: BorderSide(width: 2, color: color))),
      validator: (val) => val == null || val.isEmpty ? localizations.cannotBeEmpty : null,
    );
  }
}
